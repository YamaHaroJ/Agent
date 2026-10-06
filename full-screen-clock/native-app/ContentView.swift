import SwiftUI
import WebKit
import UIKit
import MediaPlayer
import PhotosUI
import Darwin

struct ContentView: View {
    var body: some View {
        ClockViewController()
            .ignoresSafeArea()
            .background(Color.black)
    }
}

struct ClockViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> FullScreenClockViewController {
        FullScreenClockViewController()
    }

    func updateUIViewController(
        _ uiViewController: FullScreenClockViewController,
        context: Context
    ) {}
}

final class FullScreenClockViewController:
    UIViewController,
    WKNavigationDelegate,
    PHPickerViewControllerDelegate
{
    // BACKGROUND_PHOTO_SETTINGS
    private let backgroundFileName = "clock-background.jpg"

    private var backgroundImageView: UIImageView!
    private var webView: WKWebView!
    private var errorLabel: UILabel!

    private var mediaControls: UIVisualEffectView!
    private var previousButton: UIButton!
    private var playPauseButton: UIButton!
    private var nextButton: UIButton!
    private var volumeView: MPVolumeView!

    private var settingsButton: UIButton!

    // SHIFT_TIMER
    private var shiftPanel: UIVisualEffectView!
    private var shiftTimerLabel: UILabel!
    private var clockInButton: UIButton!
    private var clockOutButton: UIButton!
    private var saveShiftButton: UIButton!
    private var shiftLogButton: UIButton!
    private var shiftTimer: Timer?

    private var shiftStartDate: Date?
    private var activeSegmentStart: Date?
    private var accumulatedShiftSeconds: TimeInterval = 0
    private var lastClockOutDate: Date?
    private weak var shiftLogViewer: UIViewController?
    private weak var shiftLogStack: UIStackView?

    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var mediaRemoteSendCommand: MRMediaRemoteSendCommand?

    private typealias MRMediaRemoteSendCommand =
        @convention(c) (Int32, UnsafeRawPointer?) -> UInt8

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        setupBackground()
        setupWebClock()
        setupErrorLabel()
        setupMediaRemote()
        setupMediaControls()
        setupSettingsButton()
        setupShiftControls()
        restoreShiftState()
        loadSavedBackground()

        UIApplication.shared.isIdleTimerDisabled = true
        loadClock()
    }

    // MARK: - Shift timer

    private struct ShiftRecord: Codable {
        let id: UUID
        let start: Date
        let end: Date
        let workedSeconds: TimeInterval
        let notes: String
    }

    private enum ShiftDefaultsKey {
        static let start = "clock.shift.start"
        static let activeStart = "clock.shift.activeStart"
        static let accumulated = "clock.shift.accumulated"
        static let lastClockOut = "clock.shift.lastClockOut"
    }

    private func setupShiftControls() {
        shiftPanel = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemThinMaterialDark)
        )
        shiftPanel.translatesAutoresizingMaskIntoConstraints = false
        shiftPanel.layer.cornerRadius = 18
        shiftPanel.clipsToBounds = true
        shiftPanel.layer.borderWidth = 1
        shiftPanel.layer.borderColor =
            UIColor.white.withAlphaComponent(0.16).cgColor

        shiftTimerLabel = UILabel()
        shiftTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        shiftTimerLabel.text = "00:00:00"
        shiftTimerLabel.textColor = .white
        shiftTimerLabel.font = .monospacedDigitSystemFont(
            ofSize: 14,
            weight: .semibold
        )
        shiftTimerLabel.textAlignment = .center

        clockInButton = makeShiftButton(
            title: "IN",
            symbol: "play.fill",
            action: #selector(clockIn)
        )
        clockOutButton = makeShiftButton(
            title: "OUT",
            symbol: "pause.fill",
            action: #selector(clockOut)
        )
        saveShiftButton = makeShiftButton(
            title: nil,
            symbol: "square.and.arrow.down",
            action: #selector(promptToSaveShift)
        )
        saveShiftButton.accessibilityLabel = "Save Shift"

        shiftLogButton = makeShiftButton(
            title: nil,
            symbol: "doc.text",
            action: #selector(openShiftLog)
        )
        shiftLogButton.accessibilityLabel = "Open Shift Log"

        let row = UIStackView(
            arrangedSubviews: [
                shiftTimerLabel,
                clockInButton,
                clockOutButton,
                saveShiftButton,
                shiftLogButton
            ]
        )
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.distribution = .fill

        shiftPanel.contentView.addSubview(row)
        view.addSubview(shiftPanel)

        NSLayoutConstraint.activate([
            shiftPanel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 14
            ),
            shiftPanel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 10
            ),
            shiftPanel.widthAnchor.constraint(equalToConstant: 300),
            shiftPanel.heightAnchor.constraint(equalToConstant: 52),

            row.leadingAnchor.constraint(
                equalTo: shiftPanel.contentView.leadingAnchor,
                constant: 10
            ),
            row.trailingAnchor.constraint(
                equalTo: shiftPanel.contentView.trailingAnchor,
                constant: -10
            ),
            row.centerYAnchor.constraint(
                equalTo: shiftPanel.contentView.centerYAnchor
            ),

            shiftTimerLabel.widthAnchor.constraint(equalToConstant: 78),
            clockInButton.widthAnchor.constraint(equalToConstant: 46),
            clockOutButton.widthAnchor.constraint(equalToConstant: 52),
            saveShiftButton.widthAnchor.constraint(equalToConstant: 36),
            shiftLogButton.widthAnchor.constraint(equalToConstant: 36),

            clockInButton.heightAnchor.constraint(equalToConstant: 36),
            clockOutButton.heightAnchor.constraint(equalToConstant: 36),
            saveShiftButton.heightAnchor.constraint(equalToConstant: 36),
            shiftLogButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        shiftTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            self?.refreshShiftUI()
        }
    }

    private func makeShiftButton(
        title: String?,
        symbol: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        button.layer.cornerRadius = 11

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: .semibold
            )
        )
        configuration.imagePadding = 4
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 4,
            leading: 5,
            bottom: 4,
            trailing: 5
        )

        if let title {
            configuration.title = title
            configuration.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = .systemFont(
                        ofSize: 10,
                        weight: .bold
                    )
                    return outgoing
                }
        }

        button.configuration = configuration
        button.addTarget(
            self,
            action: action,
            for: .touchUpInside
        )

        return button
    }

    @objc private func clockIn() {
        guard activeSegmentStart == nil else {
            return
        }

        let now = Date()

        if shiftStartDate == nil {
            shiftStartDate = now
            accumulatedShiftSeconds = 0
            lastClockOutDate = nil
        }

        activeSegmentStart = now
        persistShiftState()
        refreshShiftUI()
    }

    @objc private func clockOut() {
        guard let activeSegmentStart else {
            return
        }

        let now = Date()
        accumulatedShiftSeconds +=
            now.timeIntervalSince(activeSegmentStart)

        self.activeSegmentStart = nil
        lastClockOutDate = now

        persistShiftState()
        refreshShiftUI()
    }

    @objc private func promptToSaveShift() {
        guard shiftStartDate != nil else {
            showShiftAlert(
                title: "No Shift",
                message: "Clock in before saving a shift."
            )
            return
        }

        if activeSegmentStart != nil {
            clockOut()
        }

        let alert = UIAlertController(
            title: "Save Shift",
            message: "What did you do during this shift?",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "Calls, applications, follow-ups..."
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
        }

        alert.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel
            )
        )

        alert.addAction(
            UIAlertAction(
                title: "Save",
                style: .default
            ) { [weak self, weak alert] _ in
                guard let self else {
                    return
                }

                let notes =
                    alert?.textFields?.first?.text?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""

                self.saveCurrentShift(notes: notes)
            }
        )

        present(alert, animated: true)
    }

    private func saveCurrentShift(notes: String) {
        guard let start = shiftStartDate else {
            return
        }

        let end = lastClockOutDate ?? Date()
        let record = ShiftRecord(
            id: UUID(),
            start: start,
            end: end,
            workedSeconds: max(0, accumulatedShiftSeconds),
            notes: notes
        )

        do {
            var records = try loadShiftRecords()
            records.append(record)
            try saveShiftRecords(records)
            resetShiftState()
        } catch {
            showShiftAlert(
                title: "Couldn't Save Shift",
                message: error.localizedDescription
            )
        }
    }

    @objc private func openShiftLog() {
        let viewer = UIViewController()
        viewer.view.backgroundColor = UIColor(
            red: 0.08,
            green: 0.085,
            blue: 0.09,
            alpha: 1
        )
        viewer.title = "Shift Log"

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.layoutMargins = UIEdgeInsets(
            top: 18,
            left: 18,
            bottom: 28,
            right: 18
        )
        stack.isLayoutMarginsRelativeArrangement = true

        scroll.addSubview(stack)
        viewer.view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: viewer.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: viewer.view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: viewer.view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: viewer.view.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        let nav = UINavigationController(
            rootViewController: viewer
        )
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = CGSize(width: 720, height: 620)

        viewer.navigationItem.leftBarButtonItem =
            UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeShiftLogViewer)
            )

        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(promptToAddPastShift)
        )

        let shareButton = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareShiftLogFromViewer)
        )

        viewer.navigationItem.rightBarButtonItems = [
            shareButton,
            addButton
        ]

        shiftLogViewer = viewer
        shiftLogStack = stack
        refreshShiftLogViewer()

        present(nav, animated: true)
    }

    private func refreshShiftLogViewer() {
        guard let stack = shiftLogStack else {
            return
        }

        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        do {
            let records = try loadShiftRecords()
                .sorted { $0.start > $1.start }

            let summary = makeShiftSummaryView(records: records)
            stack.addArrangedSubview(summary)

            if records.isEmpty {
                let empty = UILabel()
                empty.text = "No saved shifts yet.\nTap + to add a past shift."
                empty.textColor = UIColor.white.withAlphaComponent(0.55)
                empty.font = .systemFont(ofSize: 16, weight: .medium)
                empty.numberOfLines = 0
                empty.textAlignment = .center
                empty.heightAnchor.constraint(equalToConstant: 130).isActive = true
                stack.addArrangedSubview(empty)
                return
            }

            for record in records {
                stack.addArrangedSubview(
                    makeShiftCard(record: record)
                )
            }
        } catch {
            let label = UILabel()
            label.text = "Couldn't load shifts.\n\(error.localizedDescription)"
            label.textColor = .systemRed
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
    }

    private func makeShiftSummaryView(
        records: [ShiftRecord]
    ) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.055)
        container.layer.cornerRadius = 16

        let totalSeconds = records.reduce(0) {
            $0 + $1.workedSeconds
        }

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = records.count == 1
            ? "1 saved shift"
            : "\(records.count) saved shifts"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .bold)

        let total = UILabel()
        total.translatesAutoresizingMaskIntoConstraints = false
        total.text = "Total logged: \(formattedShiftDuration(totalSeconds))"
        total.textColor = UIColor.white.withAlphaComponent(0.58)
        total.font = .systemFont(ofSize: 14, weight: .medium)

        container.addSubview(title)
        container.addSubview(total)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 13),

            total.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            total.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            total.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            total.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -13)
        ])

        return container
    }

    private func makeShiftCard(
        record: ShiftRecord
    ) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.075)
        card.layer.cornerRadius = 16

        let date = UILabel()
        date.translatesAutoresizingMaskIntoConstraints = false
        date.text = shiftDateFormatter.string(from: record.start)
        date.textColor = .white
        date.font = .systemFont(ofSize: 18, weight: .bold)

        let time = UILabel()
        time.translatesAutoresizingMaskIntoConstraints = false
        time.text =
            "\(shiftTimeFormatter.string(from: record.start)) – " +
            "\(shiftTimeFormatter.string(from: record.end))  ·  " +
            formattedShiftDuration(record.workedSeconds)
        time.textColor = UIColor.white.withAlphaComponent(0.68)
        time.font = .monospacedDigitSystemFont(
            ofSize: 14,
            weight: .medium
        )

        let notes = UILabel()
        notes.translatesAutoresizingMaskIntoConstraints = false
        notes.text = record.notes.isEmpty
            ? "No notes"
            : record.notes
        notes.textColor = record.notes.isEmpty
            ? UIColor.white.withAlphaComponent(0.34)
            : UIColor.white.withAlphaComponent(0.88)
        notes.font = .systemFont(ofSize: 15, weight: .regular)
        notes.numberOfLines = 0

        let editButton = UIButton(type: .system)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.tintColor = .white
        editButton.setImage(
            UIImage(systemName: "pencil"),
            for: .normal
        )
        editButton.accessibilityLabel = "Edit Shift"
        editButton.addAction(
            UIAction { [weak self] _ in
                self?.promptToEditShift(record)
            },
            for: .touchUpInside
        )

        let deleteButton = UIButton(type: .system)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.tintColor = .systemRed
        deleteButton.setImage(
            UIImage(systemName: "trash"),
            for: .normal
        )
        deleteButton.accessibilityLabel = "Delete Shift"
        deleteButton.addAction(
            UIAction { [weak self] _ in
                self?.confirmDeleteShift(record)
            },
            for: .touchUpInside
        )

        card.addSubview(date)
        card.addSubview(time)
        card.addSubview(notes)
        card.addSubview(editButton)
        card.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            date.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            date.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            date.trailingAnchor.constraint(
                lessThanOrEqualTo: editButton.leadingAnchor,
                constant: -8
            ),

            deleteButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            deleteButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            deleteButton.widthAnchor.constraint(equalToConstant: 36),
            deleteButton.heightAnchor.constraint(equalToConstant: 36),

            editButton.trailingAnchor.constraint(
                equalTo: deleteButton.leadingAnchor,
                constant: -2
            ),
            editButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            editButton.widthAnchor.constraint(equalToConstant: 36),
            editButton.heightAnchor.constraint(equalToConstant: 36),

            time.leadingAnchor.constraint(equalTo: date.leadingAnchor),
            time.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            time.topAnchor.constraint(equalTo: date.bottomAnchor, constant: 3),

            notes.leadingAnchor.constraint(equalTo: date.leadingAnchor),
            notes.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            notes.topAnchor.constraint(equalTo: time.bottomAnchor, constant: 10),
            notes.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        return card
    }

    private func promptToEditShift(
        _ record: ShiftRecord
    ) {
        guard let viewer = shiftLogViewer else {
            return
        }

        let editor = UIViewController()
        editor.view.backgroundColor = UIColor(
            red: 0.075,
            green: 0.08,
            blue: 0.085,
            alpha: 1
        )
        editor.preferredContentSize = CGSize(
            width: 720,
            height: 330
        )

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Edit Shift"
        title.textColor = .white
        title.font = .systemFont(ofSize: 28, weight: .bold)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Change the date, times, or notes."
        subtitle.textColor = UIColor.white.withAlphaComponent(0.55)
        subtitle.font = .systemFont(ofSize: 15, weight: .medium)

        let dateField = makeShiftEditorField(
            title: "Date",
            text: pastShiftDateFormatter.string(from: record.start),
            placeholder: "10/5/2026"
        )
        dateField.keyboardType = .numbersAndPunctuation

        let startField = makeShiftEditorField(
            title: "Clock In",
            text: shiftTimeFormatter.string(from: record.start),
            placeholder: "9:00 AM"
        )

        let endField = makeShiftEditorField(
            title: "Clock Out",
            text: shiftTimeFormatter.string(from: record.end),
            placeholder: "5:00 PM"
        )

        let notesField = UITextView()
        notesField.translatesAutoresizingMaskIntoConstraints = false
        notesField.text = record.notes
        notesField.textColor = .white
        notesField.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        notesField.font = .systemFont(ofSize: 17, weight: .regular)
        notesField.layer.cornerRadius = 12
        notesField.textContainerInset = UIEdgeInsets(
            top: 10,
            left: 10,
            bottom: 10,
            right: 10
        )

        let notesLabel = UILabel()
        notesLabel.translatesAutoresizingMaskIntoConstraints = false
        notesLabel.text = "What I did"
        notesLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        notesLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        var cancelConfig = UIButton.Configuration.filled()
        cancelConfig.title = "Cancel"
        cancelConfig.baseForegroundColor = .white
        cancelConfig.baseBackgroundColor =
            UIColor.white.withAlphaComponent(0.12)
        cancelConfig.cornerStyle = .large
        cancelButton.configuration = cancelConfig

        let saveButton = UIButton(type: .system)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        var saveConfig = UIButton.Configuration.filled()
        saveConfig.title = "Save Changes"
        saveConfig.baseForegroundColor = .black
        saveConfig.baseBackgroundColor = .white
        saveConfig.cornerStyle = .large
        saveButton.configuration = saveConfig

        let fieldsRow = UIStackView(
            arrangedSubviews: [
                dateField,
                startField,
                endField
            ]
        )
        fieldsRow.translatesAutoresizingMaskIntoConstraints = false
        fieldsRow.axis = .horizontal
        fieldsRow.spacing = 10
        fieldsRow.distribution = .fillEqually

        let leftColumn = UIStackView(
            arrangedSubviews: [
                fieldsRow
            ]
        )
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.axis = .vertical
        leftColumn.spacing = 10

        let notesColumn = UIStackView(
            arrangedSubviews: [
                notesLabel,
                notesField
            ]
        )
        notesColumn.translatesAutoresizingMaskIntoConstraints = false
        notesColumn.axis = .vertical
        notesColumn.spacing = 7

        let formRow = UIStackView(
            arrangedSubviews: [
                leftColumn,
                notesColumn
            ]
        )
        formRow.translatesAutoresizingMaskIntoConstraints = false
        formRow.axis = .horizontal
        formRow.spacing = 14
        formRow.distribution = .fillEqually

        let buttons = UIStackView(
            arrangedSubviews: [
                cancelButton,
                saveButton
            ]
        )
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually

        editor.view.addSubview(title)
        editor.view.addSubview(subtitle)
        editor.view.addSubview(formRow)
        editor.view.addSubview(buttons)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(
                equalTo: editor.view.topAnchor,
                constant: 20
            ),
            title.leadingAnchor.constraint(
                equalTo: editor.view.leadingAnchor,
                constant: 22
            ),
            title.trailingAnchor.constraint(
                lessThanOrEqualTo: editor.view.trailingAnchor,
                constant: -22
            ),

            subtitle.topAnchor.constraint(
                equalTo: title.bottomAnchor,
                constant: 2
            ),
            subtitle.leadingAnchor.constraint(
                equalTo: title.leadingAnchor
            ),
            subtitle.trailingAnchor.constraint(
                lessThanOrEqualTo: editor.view.trailingAnchor,
                constant: -22
            ),

            formRow.topAnchor.constraint(
                equalTo: subtitle.bottomAnchor,
                constant: 18
            ),
            formRow.leadingAnchor.constraint(
                equalTo: editor.view.leadingAnchor,
                constant: 22
            ),
            formRow.trailingAnchor.constraint(
                equalTo: editor.view.trailingAnchor,
                constant: -22
            ),
            formRow.heightAnchor.constraint(equalToConstant: 130),

            notesField.heightAnchor.constraint(equalToConstant: 101),

            buttons.topAnchor.constraint(
                equalTo: formRow.bottomAnchor,
                constant: 16
            ),
            buttons.leadingAnchor.constraint(
                equalTo: editor.view.leadingAnchor,
                constant: 22
            ),
            buttons.trailingAnchor.constraint(
                equalTo: editor.view.trailingAnchor,
                constant: -22
            ),
            buttons.heightAnchor.constraint(equalToConstant: 48)
        ])

        let nav = UINavigationController(
            rootViewController: editor
        )
        nav.setNavigationBarHidden(true, animated: false)
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = CGSize(
            width: 720,
            height: 330
        )

        cancelButton.addAction(
            UIAction { [weak nav] _ in
                nav?.dismiss(animated: true)
            },
            for: .touchUpInside
        )

        saveButton.addAction(
            UIAction { [weak self, weak nav, weak dateField, weak startField, weak endField, weak notesField] _ in
                guard
                    let self,
                    let dateText = dateField?.text,
                    let startText = startField?.text,
                    let endText = endField?.text,
                    let notes = notesField?.text
                else {
                    return
                }

                nav?.dismiss(animated: true) {
                    self.updateShift(
                        record,
                        dateText: dateText,
                        startText: startText,
                        endText: endText,
                        notes: notes
                    )
                }
            },
            for: .touchUpInside
        )

        viewer.present(nav, animated: true)
    }

    private func makeShiftEditorField(
        title: String,
        text: String,
        placeholder: String
    ) -> UITextField {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.text = text
        field.placeholder = placeholder
        field.textColor = .white
        field.font = .systemFont(ofSize: 17, weight: .semibold)
        field.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        field.layer.cornerRadius = 12
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = .allCharacters
        field.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let label = UILabel()
        label.text = title
        label.textColor = UIColor.white.withAlphaComponent(0.55)
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.sizeToFit()

        let container = UIView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: 70,
                height: 24
            )
        )
        label.frame = CGRect(
            x: 10,
            y: 0,
            width: 60,
            height: 24
        )
        container.addSubview(label)
        field.leftView = container
        field.leftViewMode = .always

        return field
    }

    private func updateShift(
        _ record: ShiftRecord,
        dateText: String,
        startText: String,
        endText: String,
        notes: String
    ) {
        let date = dateText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let startTime = startText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let endTime = endText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "M/d/yyyy h:mm a"

        guard
            let start = parser.date(from: "\(date) \(startTime)"),
            let end = parser.date(from: "\(date) \(endTime)")
        else {
            showShiftLogError(
                "Use a date like 10/5/2026 and times like 9:00 AM."
            )
            return
        }

        guard end > start else {
            showShiftLogError(
                "Clock Out must be later than Clock In."
            )
            return
        }

        let updated = ShiftRecord(
            id: record.id,
            start: start,
            end: end,
            workedSeconds: end.timeIntervalSince(start),
            notes: notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )

        do {
            var records = try loadShiftRecords()

            guard let index = records.firstIndex(
                where: { $0.id == record.id }
            ) else {
                showShiftLogError(
                    "That saved shift could not be found."
                )
                return
            }

            records[index] = updated
            try saveShiftRecords(records)
            refreshShiftLogViewer()
        } catch {
            showShiftLogError(error.localizedDescription)
        }
    }

    private func confirmDeleteShift(
        _ record: ShiftRecord
    ) {
        guard let viewer = shiftLogViewer else {
            return
        }

        let alert = UIAlertController(
            title: "Delete Shift?",
            message:
                shiftDateFormatter.string(from: record.start) +
                " · " +
                formattedShiftDuration(record.workedSeconds),
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel
            )
        )

        alert.addAction(
            UIAlertAction(
                title: "Delete",
                style: .destructive
            ) { [weak self] _ in
                self?.deleteShift(id: record.id)
            }
        )

        viewer.present(alert, animated: true)
    }

    private func deleteShift(id: UUID) {
        do {
            var records = try loadShiftRecords()
            records.removeAll { $0.id == id }
            try saveShiftRecords(records)
            refreshShiftLogViewer()
        } catch {
            showShiftLogError(error.localizedDescription)
        }
    }

    @objc private func promptToAddPastShift() {
        guard let viewer = shiftLogViewer else {
            return
        }

        let alert = UIAlertController(
            title: "Add Past Shift",
            message: "Enter the date and times.",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "Date (10/5/2026)"
            field.text = self.pastShiftDateFormatter.string(from: Date())
            field.keyboardType = .numbersAndPunctuation
        }

        alert.addTextField { field in
            field.placeholder = "Clock in (9:00 AM)"
            field.text = "9:00 AM"
            field.autocapitalizationType = .allCharacters
        }

        alert.addTextField { field in
            field.placeholder = "Clock out (5:00 PM)"
            field.text = "5:00 PM"
            field.autocapitalizationType = .allCharacters
        }

        alert.addTextField { field in
            field.placeholder = "What did you do?"
            field.autocapitalizationType = .sentences
        }

        alert.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel
            )
        )

        alert.addAction(
            UIAlertAction(
                title: "Add",
                style: .default
            ) { [weak self, weak alert] _ in
                guard
                    let self,
                    let fields = alert?.textFields,
                    fields.count == 4
                else {
                    return
                }

                self.addPastShift(
                    dateText: fields[0].text ?? "",
                    startText: fields[1].text ?? "",
                    endText: fields[2].text ?? "",
                    notes: fields[3].text ?? ""
                )
            }
        )

        viewer.present(alert, animated: true)
    }

    private func addPastShift(
        dateText: String,
        startText: String,
        endText: String,
        notes: String
    ) {
        let date = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let startTime = startText.trimmingCharacters(in: .whitespacesAndNewlines)
        let endTime = endText.trimmingCharacters(in: .whitespacesAndNewlines)

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "M/d/yyyy h:mm a"

        guard
            let start = parser.date(from: "\(date) \(startTime)"),
            let end = parser.date(from: "\(date) \(endTime)")
        else {
            showShiftLogError(
                "Use a date like 10/5/2026 and times like 9:00 AM."
            )
            return
        }

        guard end > start else {
            showShiftLogError(
                "Clock Out must be later than Clock In."
            )
            return
        }

        let record = ShiftRecord(
            id: UUID(),
            start: start,
            end: end,
            workedSeconds: end.timeIntervalSince(start),
            notes: notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )

        do {
            var records = try loadShiftRecords()
            records.append(record)
            try saveShiftRecords(records)
            refreshShiftLogViewer()
        } catch {
            showShiftLogError(error.localizedDescription)
        }
    }

    private func showShiftLogError(
        _ message: String
    ) {
        guard let viewer = shiftLogViewer else {
            return
        }

        let alert = UIAlertController(
            title: "Shift Log",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(
                title: "OK",
                style: .default
            )
        )
        viewer.present(alert, animated: true)
    }

    @objc private func closeShiftLogViewer() {
        presentedViewController?.dismiss(animated: true)
    }

    @objc private func shareShiftLogFromViewer() {
        guard
            let nav = presentedViewController as? UINavigationController,
            let source = nav.topViewController
        else {
            return
        }

        do {
            let records = try loadShiftRecords()
            try writeReadableShiftDocument(records)
            shareShiftLog(from: source)
        } catch {
            showShiftLogError(error.localizedDescription)
        }
    }

    private func shareShiftLog(
        from source: UIViewController
    ) {
        let sheet = UIActivityViewController(
            activityItems: [shiftReadableLogURL],
            applicationActivities: nil
        )

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = source.view
            popover.sourceRect = CGRect(
                x: source.view.bounds.midX,
                y: source.view.bounds.midY,
                width: 1,
                height: 1
            )
        }

        source.present(sheet, animated: true)
    }

    private var shiftRecordsURL: URL {
        documentsDirectory.appendingPathComponent("Shift Records.json")
    }

    private var shiftReadableLogURL: URL {
        documentsDirectory.appendingPathComponent("Shift Log.txt")
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
    }

    private func loadShiftRecords() throws -> [ShiftRecord] {
        guard FileManager.default.fileExists(
            atPath: shiftRecordsURL.path
        ) else {
            return []
        }

        let data = try Data(contentsOf: shiftRecordsURL)
        return try JSONDecoder().decode(
            [ShiftRecord].self,
            from: data
        )
    }

    private func saveShiftRecords(
        _ records: [ShiftRecord]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(records)
        try data.write(
            to: shiftRecordsURL,
            options: .atomic
        )

        try writeReadableShiftDocument(records)
    }

    private func writeReadableShiftDocument(
        _ records: [ShiftRecord]
    ) throws {
        let sorted = records.sorted {
            $0.start < $1.start
        }

        var lines: [String] = [
            "SHIFT LOG",
            "=========",
            ""
        ]

        for record in sorted {
            lines.append(
                shiftDateFormatter.string(from: record.start)
            )
            lines.append(
                "  \(shiftTimeFormatter.string(from: record.start)) – " +
                "\(shiftTimeFormatter.string(from: record.end))"
            )
            lines.append(
                "  Total: \(formattedShiftDuration(record.workedSeconds))"
            )

            if !record.notes.isEmpty {
                lines.append(
                    "  What I did: \(record.notes)"
                )
            }

            lines.append("")
        }

        if sorted.isEmpty {
            lines.append("No saved shifts.")
            lines.append("")
        }

        let total = sorted.reduce(0) {
            $0 + $1.workedSeconds
        }

        lines.append(
            "TOTAL LOGGED: \(formattedShiftDuration(total))"
        )
        lines.append("")

        try lines.joined(separator: "\n").write(
            to: shiftReadableLogURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private var shiftDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var shiftTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private var pastShiftDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d/yyyy"
        return formatter
    }

    private func restoreShiftState() {
        let defaults = UserDefaults.standard

        if let value = defaults.object(
            forKey: ShiftDefaultsKey.start
        ) as? Double {
            shiftStartDate = Date(
                timeIntervalSince1970: value
            )
        }

        if let value = defaults.object(
            forKey: ShiftDefaultsKey.activeStart
        ) as? Double {
            activeSegmentStart = Date(
                timeIntervalSince1970: value
            )
        }

        accumulatedShiftSeconds = defaults.double(
            forKey: ShiftDefaultsKey.accumulated
        )

        if let value = defaults.object(
            forKey: ShiftDefaultsKey.lastClockOut
        ) as? Double {
            lastClockOutDate = Date(
                timeIntervalSince1970: value
            )
        }

        refreshShiftUI()
    }

    private func persistShiftState() {
        let defaults = UserDefaults.standard

        if let shiftStartDate {
            defaults.set(
                shiftStartDate.timeIntervalSince1970,
                forKey: ShiftDefaultsKey.start
            )
        } else {
            defaults.removeObject(
                forKey: ShiftDefaultsKey.start
            )
        }

        if let activeSegmentStart {
            defaults.set(
                activeSegmentStart.timeIntervalSince1970,
                forKey: ShiftDefaultsKey.activeStart
            )
        } else {
            defaults.removeObject(
                forKey: ShiftDefaultsKey.activeStart
            )
        }

        defaults.set(
            accumulatedShiftSeconds,
            forKey: ShiftDefaultsKey.accumulated
        )

        if let lastClockOutDate {
            defaults.set(
                lastClockOutDate.timeIntervalSince1970,
                forKey: ShiftDefaultsKey.lastClockOut
            )
        } else {
            defaults.removeObject(
                forKey: ShiftDefaultsKey.lastClockOut
            )
        }
    }

    private func resetShiftState() {
        shiftStartDate = nil
        activeSegmentStart = nil
        accumulatedShiftSeconds = 0
        lastClockOutDate = nil

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ShiftDefaultsKey.start)
        defaults.removeObject(forKey: ShiftDefaultsKey.activeStart)
        defaults.removeObject(forKey: ShiftDefaultsKey.accumulated)
        defaults.removeObject(forKey: ShiftDefaultsKey.lastClockOut)

        refreshShiftUI()
    }

    private func currentShiftSeconds() -> TimeInterval {
        var seconds = accumulatedShiftSeconds

        if let activeSegmentStart {
            seconds += Date().timeIntervalSince(activeSegmentStart)
        }

        return max(0, seconds)
    }

    private func refreshShiftUI() {
        guard shiftTimerLabel != nil else {
            return
        }

        shiftTimerLabel.text =
            formattedTimer(currentShiftSeconds())

        let running = activeSegmentStart != nil
        let hasShift = shiftStartDate != nil

        clockInButton.isEnabled = !running
        clockOutButton.isEnabled = running
        saveShiftButton.isEnabled = hasShift

        clockInButton.alpha = running ? 0.35 : 1
        clockOutButton.alpha = running ? 1 : 0.35
        saveShiftButton.alpha = hasShift ? 1 : 0.35
    }

    private func formattedTimer(
        _ seconds: TimeInterval
    ) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        return String(
            format: "%02d:%02d:%02d",
            hours,
            minutes,
            secs
        )
    }

    private func formattedShiftDuration(
        _ seconds: TimeInterval
    ) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(minutes)m"
    }

    private func showShiftAlert(
        title: String,
        message: String
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: "OK",
                style: .default
            )
        )

        present(alert, animated: true)
    }

    // MARK: - Background photo

    private func setupBackground() {
        backgroundImageView = UIImageView()
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundImageView.backgroundColor = .black
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true

        view.addSubview(backgroundImageView)

        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            backgroundImageView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            backgroundImageView.topAnchor.constraint(
                equalTo: view.topAnchor
            ),
            backgroundImageView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])
    }

    private var backgroundFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(backgroundFileName)
    }

    private func loadSavedBackground() {
        guard
            let url = backgroundFileURL,
            let data = try? Data(contentsOf: url),
            let image = UIImage(data: data)
        else {
            backgroundImageView.image = nil
            backgroundImageView.backgroundColor = .black
            return
        }

        backgroundImageView.image = image
        backgroundImageView.backgroundColor = .black
    }

    private func saveBackground(_ image: UIImage) {
        guard
            let url = backgroundFileURL,
            let data = image.jpegData(compressionQuality: 0.92)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }

        backgroundImageView.image = image
        backgroundImageView.backgroundColor = .black
    }

    private func removeBackground() {
        if let url = backgroundFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        backgroundImageView.image = nil
        backgroundImageView.backgroundColor = .black
    }

    private func setupSettingsButton() {
        settingsButton = UIButton(type: .system)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.tintColor = .white
        settingsButton.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        settingsButton.layer.cornerRadius = 22
        settingsButton.layer.borderWidth = 1
        settingsButton.layer.borderColor =
            UIColor.white.withAlphaComponent(0.18).cgColor

        settingsButton.setImage(
            UIImage(
                systemName: "gearshape.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 19,
                    weight: .semibold
                )
            ),
            for: .normal
        )

        settingsButton.accessibilityLabel = "Clock Settings"
        settingsButton.addTarget(
            self,
            action: #selector(openSettings),
            for: .touchUpInside
        )

        view.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 10
            ),
            settingsButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -14
            ),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func openSettings() {
        let sheet = UIAlertController(
            title: "Clock Settings",
            message: nil,
            preferredStyle: .actionSheet
        )

        sheet.addAction(
            UIAlertAction(
                title: "Choose Photo",
                style: .default
            ) { [weak self] _ in
                self?.openPhotoPicker()
            }
        )

        if backgroundImageView.image != nil {
            sheet.addAction(
                UIAlertAction(
                    title: "Remove Background",
                    style: .destructive
                ) { [weak self] _ in
                    self?.removeBackground()
                }
            )
        }

        sheet.addAction(
            UIAlertAction(
                title: "Change App Icon",
                style: .default
            ) { [weak self] _ in
                self?.openIconPicker()
            }
        )

        sheet.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel
            )
        )

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = settingsButton
            popover.sourceRect = settingsButton.bounds
        }

        present(sheet, animated: true)
    }

    private func openIconPicker() {
        guard UIApplication.shared.supportsAlternateIcons else {
            showIconError(
                title: "App Icons Unavailable",
                message:
                    "This build does not have the alternate icons registered."
            )
            return
        }

        let picker = UIViewController()
        picker.view.backgroundColor = UIColor(
            red: 0.07,
            green: 0.075,
            blue: 0.075,
            alpha: 1
        )
        picker.preferredContentSize = CGSize(width: 520, height: 255)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "App Icon"
        title.textColor = .white
        title.font = .systemFont(ofSize: 25, weight: .bold)
        picker.view.addSubview(title)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Tap a preview"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.58)
        subtitle.font = .systemFont(ofSize: 15, weight: .medium)
        picker.view.addSubview(subtitle)

        let current = UIApplication.shared.alternateIconName

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.spacing = 18
        picker.view.addSubview(row)

        let choices: [(String, String)] = [
            ("ClockItalicC", "Italic C"),
            ("ClockWordmark", "Clock"),
            ("ClockChromeC", "Chrome C")
        ]

        for choice in choices {
            let card = UIView()
            card.translatesAutoresizingMaskIntoConstraints = false

            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.layer.cornerRadius = 22
            button.clipsToBounds = true
            button.layer.borderWidth =
                current == choice.0 ? 4 : 1
            button.layer.borderColor =
                current == choice.0
                    ? UIColor.white.cgColor
                    : UIColor.white.withAlphaComponent(0.18).cgColor

            button.backgroundColor = .black
            button.setImage(
                makeIconPreviewPlaceholder(size: 132),
                for: .normal
            )
            button.imageView?.contentMode = .scaleAspectFill
            button.accessibilityLabel = choice.1

            loadExactIconPreview(
                named: choice.0,
                into: button
            )

            button.addAction(
                UIAction { [weak self, weak picker] _ in
                    picker?.dismiss(animated: true) {
                        self?.setAppIcon(choice.0)
                    }
                },
                for: .touchUpInside
            )

            card.addSubview(button)

            let check = UIImageView(
                image: UIImage(
                    systemName:
                        current == choice.0
                            ? "checkmark.circle.fill"
                            : "circle"
                )
            )
            check.translatesAutoresizingMaskIntoConstraints = false
            check.tintColor =
                current == choice.0
                    ? .white
                    : UIColor.white.withAlphaComponent(0.32)
            card.addSubview(check)

            NSLayoutConstraint.activate([
                card.widthAnchor.constraint(equalToConstant: 136),
                card.heightAnchor.constraint(equalToConstant: 148),

                button.topAnchor.constraint(equalTo: card.topAnchor),
                button.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                button.widthAnchor.constraint(equalToConstant: 132),
                button.heightAnchor.constraint(equalToConstant: 132),

                check.trailingAnchor.constraint(
                    equalTo: button.trailingAnchor,
                    constant: -8
                ),
                check.bottomAnchor.constraint(
                    equalTo: button.bottomAnchor,
                    constant: -8
                ),
                check.widthAnchor.constraint(equalToConstant: 24),
                check.heightAnchor.constraint(equalToConstant: 24)
            ])

            row.addArrangedSubview(card)
        }

        let defaultButton = UIButton(type: .system)
        defaultButton.translatesAutoresizingMaskIntoConstraints = false
        defaultButton.tintColor = .white
        defaultButton.setTitle(
            current == nil ? "✓ Default" : "Default",
            for: .normal
        )
        defaultButton.titleLabel?.font =
            .systemFont(ofSize: 16, weight: .semibold)
        defaultButton.addAction(
            UIAction { [weak self, weak picker] _ in
                picker?.dismiss(animated: true) {
                    self?.setAppIcon(nil)
                }
            },
            for: .touchUpInside
        )
        picker.view.addSubview(defaultButton)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(
                equalTo: picker.view.topAnchor,
                constant: 20
            ),
            title.leadingAnchor.constraint(
                equalTo: picker.view.leadingAnchor,
                constant: 24
            ),

            subtitle.topAnchor.constraint(
                equalTo: title.bottomAnchor,
                constant: 2
            ),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            row.topAnchor.constraint(
                equalTo: subtitle.bottomAnchor,
                constant: 17
            ),
            row.centerXAnchor.constraint(equalTo: picker.view.centerXAnchor),
            row.widthAnchor.constraint(equalToConstant: 446),

            defaultButton.topAnchor.constraint(
                equalTo: row.bottomAnchor,
                constant: 3
            ),
            defaultButton.centerXAnchor.constraint(
                equalTo: picker.view.centerXAnchor
            )
        ])

        picker.modalPresentationStyle = .popover

        if let popover = picker.popoverPresentationController {
            popover.sourceView = settingsButton
            popover.sourceRect = settingsButton.bounds
            popover.permittedArrowDirections = [.up, .right]
            popover.backgroundColor = picker.view.backgroundColor
        }

        present(picker, animated: true)
    }

    private func makeIconPreviewPlaceholder(
        size: CGFloat
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size)
        )

        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(
                CGRect(x: 0, y: 0, width: size, height: size)
            )

            if let symbol = UIImage(
                systemName: "arrow.down.circle"
            )?.withTintColor(
                UIColor.white.withAlphaComponent(0.28),
                renderingMode: .alwaysOriginal
            ) {
                let symbolSize = size * 0.24
                symbol.draw(
                    in: CGRect(
                        x: (size - symbolSize) / 2,
                        y: (size - symbolSize) / 2,
                        width: symbolSize,
                        height: symbolSize
                    )
                )
            }
        }
    }

    private func loadExactIconPreview(
        named iconName: String,
        into button: UIButton
    ) {
        let encodedName =
            iconName.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? iconName

        guard let url = URL(
            string:
                "https://raw.githubusercontent.com/" +
                "YamaHaroJ/Agent/main/full-screen-clock/" +
                "native-assets/\(encodedName)_master.jpg" +
                "?v=\(Int(Date().timeIntervalSince1970))"
        ) else {
            return
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 10
        )
        request.setValue(
            "no-cache",
            forHTTPHeaderField: "Cache-Control"
        )

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let data,
                let image = UIImage(data: data)
            else {
                return
            }

            DispatchQueue.main.async {
                button.setImage(
                    self.opticallyCenteredPreview(
                        image,
                        named: iconName,
                        size: 132
                    ).withRenderingMode(.alwaysOriginal),
                    for: .normal
                )
            }
        }.resume()
    }

    private func opticallyCenteredPreview(
        _ image: UIImage,
        named iconName: String,
        size: CGFloat
    ) -> UIImage {
        let placement: (scale: CGFloat, x: CGFloat, y: CGFloat)

        switch iconName {
        case "ClockItalicC":
            placement = (1.06, -0.045, 0.0)
        case "ClockWordmark":
            placement = (1.06, -0.108, 0.0)
        case "ClockChromeC":
            placement = (1.06, -0.103, 0.0)
        default:
            placement = (1.0, 0.0, 0.0)
        }

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size)
        )

        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(
                CGRect(x: 0, y: 0, width: size, height: size)
            )

            let side = size * placement.scale
            let rect = CGRect(
                x: (size - side) / 2 + size * placement.x,
                y: (size - side) / 2 + size * placement.y,
                width: side,
                height: side
            )

            image.draw(in: rect)
        }
    }

    private func setAppIcon(_ iconName: String?) {
        let requestedName = iconName

        UIApplication.shared.setAlternateIconName(
            requestedName
        ) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                if let error {
                    self.showIconError(
                        title: "Couldn't Change Icon",
                        message:
                            error.localizedDescription +
                            "\n\nThe icon is registered in the app bundle, " +
                            "but iPadOS rejected the switch."
                    )
                    return
                }

                // iPadOS should update this immediately. Verify it so a silent
                // failure cannot look like success.
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.35
                ) {
                    let actual =
                        UIApplication.shared.alternateIconName

                    if actual != requestedName {
                        self.showIconError(
                            title: "Icon Didn't Switch",
                            message:
                                "iPadOS accepted the request but still reports " +
                                "the previous icon. Reopen Clock and try once more."
                        )
                    }
                }
            }
        }
    }

    private func showIconError(
        title: String,
        message: String
    ) {
        guard presentedViewController == nil else {
            dismiss(animated: true) { [weak self] in
                self?.showIconError(title: title, message: message)
            }
            return
        }

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(
                title: "OK",
                style: .default
            )
        )
        present(alert, animated: true)
    }

    private func openPhotoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self

        present(picker, animated: true)
    }

    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        picker.dismiss(animated: true)

        guard
            let provider = results.first?.itemProvider,
            provider.canLoadObject(ofClass: UIImage.self)
        else {
            return
        }

        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else {
                return
            }

            DispatchQueue.main.async {
                self?.saveBackground(image)
            }
        }
    }

    // MARK: - Web clock

    private func setupWebClock() {
        let config = WKWebViewConfiguration()

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupErrorLabel() {
        errorLabel = UILabel()
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = .white
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true

        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor,
                constant: 30
            ),
            errorLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor,
                constant: -30
            )
        ])
    }

    private func loadClock() {
        var components = URLComponents(
            string: "https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/index.html"
        )!

        components.queryItems = [
            URLQueryItem(
                name: "v",
                value: String(Int(Date().timeIntervalSince1970))
            )
        ]

        var request = URLRequest(
            url: components.url!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else {
                return
            }

            guard
                let data,
                var html = String(data: data, encoding: .utf8)
            else {
                DispatchQueue.main.async {
                    self.errorLabel.text =
                        "Clock could not load.\n\n" +
                        (error?.localizedDescription ?? "Unknown network error")
                    self.errorLabel.isHidden = false
                }
                return
            }

            let nativeTransparencyCSS = """
            <style id="native-photo-background">
              html, body, #app {
                background: transparent !important;
                background-color: transparent !important;
              }
            </style>
            """

            html = html.replacingOccurrences(
                of: "</head>",
                with: nativeTransparencyCSS + "</head>"
            )

            DispatchQueue.main.async {
                self.errorLabel.isHidden = true
                self.webView.loadHTMLString(
                    html,
                    baseURL: URL(
                        string: "https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/"
                    )
                )
            }
        }.resume()
    }

    // MARK: - Native media controls

    private func setupMediaRemote() {
        let frameworkPath =
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            return
        }

        mediaRemoteHandle = handle

        if let commandSymbol = dlsym(handle, "MRMediaRemoteSendCommand") {
            mediaRemoteSendCommand = unsafeBitCast(
                commandSymbol,
                to: MRMediaRemoteSendCommand.self
            )
        }
    }

    private func setupMediaControls() {
        mediaControls = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemThinMaterialDark)
        )
        mediaControls.translatesAutoresizingMaskIntoConstraints = false
        mediaControls.layer.cornerRadius = 28
        mediaControls.clipsToBounds = true

        previousButton = makeMediaButton(
            systemName: "backward.end.fill",
            accessibilityLabel: "Previous Track",
            action: #selector(previousTrack)
        )

        playPauseButton = makeMediaButton(
            systemName: "playpause.fill",
            accessibilityLabel: "Play or Pause",
            action: #selector(toggleExternalPlayback)
        )

        nextButton = makeMediaButton(
            systemName: "forward.end.fill",
            accessibilityLabel: "Next Track",
            action: #selector(nextTrack)
        )

        let buttonRow = UIStackView(
            arrangedSubviews: [
                previousButton,
                playPauseButton,
                nextButton
            ]
        )
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.distribution = .equalCentering
        buttonRow.spacing = 34

        volumeView = MPVolumeView(frame: .zero)
        volumeView.translatesAutoresizingMaskIntoConstraints = false
        volumeView.showsVolumeSlider = true
        volumeView.showsRouteButton = false
        volumeView.tintColor = .white

        mediaControls.contentView.addSubview(buttonRow)
        mediaControls.contentView.addSubview(volumeView)
        view.addSubview(mediaControls)

        NSLayoutConstraint.activate([
            mediaControls.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mediaControls.topAnchor.constraint(
                equalTo: view.centerYAnchor,
                constant: 125
            ),
            mediaControls.widthAnchor.constraint(equalToConstant: 340),
            mediaControls.heightAnchor.constraint(equalToConstant: 126),

            buttonRow.topAnchor.constraint(
                equalTo: mediaControls.contentView.topAnchor,
                constant: 10
            ),
            buttonRow.centerXAnchor.constraint(
                equalTo: mediaControls.contentView.centerXAnchor
            ),
            buttonRow.widthAnchor.constraint(equalToConstant: 220),
            buttonRow.heightAnchor.constraint(equalToConstant: 54),

            previousButton.widthAnchor.constraint(equalToConstant: 50),
            previousButton.heightAnchor.constraint(equalToConstant: 50),

            playPauseButton.widthAnchor.constraint(equalToConstant: 54),
            playPauseButton.heightAnchor.constraint(equalToConstant: 54),

            nextButton.widthAnchor.constraint(equalToConstant: 50),
            nextButton.heightAnchor.constraint(equalToConstant: 50),

            volumeView.topAnchor.constraint(
                equalTo: buttonRow.bottomAnchor,
                constant: 10
            ),
            volumeView.centerXAnchor.constraint(
                equalTo: mediaControls.contentView.centerXAnchor
            ),
            volumeView.widthAnchor.constraint(equalToConstant: 270),
            volumeView.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func makeMediaButton(
        systemName: String,
        accessibilityLabel: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white

        button.setImage(
            UIImage(
                systemName: systemName,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 28,
                    weight: .semibold
                )
            ),
            for: .normal
        )

        button.accessibilityLabel = accessibilityLabel
        button.addTarget(
            self,
            action: action,
            for: .touchUpInside
        )

        return button
    }

    @objc private func previousTrack() {
        sendMediaCommand(5, button: previousButton)
    }

    @objc private func toggleExternalPlayback() {
        sendMediaCommand(2, button: playPauseButton)
    }

    @objc private func nextTrack() {
        sendMediaCommand(4, button: nextButton)
    }

    private func sendMediaCommand(
        _ command: Int32,
        button: UIButton
    ) {
        guard let sendCommand = mediaRemoteSendCommand else {
            showMediaControlUnavailable()
            return
        }

        let accepted = sendCommand(command, nil)

        guard accepted != 0 else {
            showMediaControlUnavailable()
            return
        }

        UIView.animate(
            withDuration: 0.08,
            animations: {
                button.transform = CGAffineTransform(
                    scaleX: 0.82,
                    y: 0.82
                )
            },
            completion: { _ in
                UIView.animate(withDuration: 0.10) {
                    button.transform = .identity
                }
            }
        )
    }

    private func showMediaControlUnavailable() {
        guard presentedViewController == nil else {
            return
        }

        let alert = UIAlertController(
            title: "Media control unavailable",
            message:
                "This iPad blocked direct control of the current media app. " +
                "The volume slider will still work normally.",
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: "OK",
                style: .default
            )
        )

        present(alert, animated: true)
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .all
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    override var shouldAutorotate: Bool {
        true
    }

    deinit {
        shiftTimer?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = false

        if let mediaRemoteHandle {
            dlclose(mediaRemoteHandle)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if
            let url = navigationAction.request.url,
            url.host?.contains("soundcloud.com") == true
        {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}
