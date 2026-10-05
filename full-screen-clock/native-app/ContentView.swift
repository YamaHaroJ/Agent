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
        loadSavedBackground()

        UIApplication.shared.isIdleTimerDisabled = true
        loadClock()
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
                    image.withRenderingMode(.alwaysOriginal),
                    for: .normal
                )
            }
        }.resume()
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
