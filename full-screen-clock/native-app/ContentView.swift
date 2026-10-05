import SwiftUI
import WebKit
import UIKit
import MediaPlayer
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

final class FullScreenClockViewController: UIViewController, WKNavigationDelegate {
    // CLOCK_ART_BRIDGE_URL
    private let bridgeBaseURL =
        URL(string: "http://Jays-MacBook-Pro.local:8765")!

    private var artworkView: UIImageView!
    private var webView: WKWebView!
    private var errorLabel: UILabel!

    private var mediaControls: UIVisualEffectView!
    private var previousButton: UIButton!
    private var playPauseButton: UIButton!
    private var nextButton: UIButton!
    private var volumeView: MPVolumeView!

    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var mediaRemoteSendCommand: MRMediaRemoteSendCommand?

    private var bridgeTimer: Timer?
    private var bridgeStatusRequestInFlight = false
    private var bridgeArtworkRequestInFlight = false
    private var lastBridgeArtworkHash: String?

    private lazy var bridgeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 4.0
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private typealias MRMediaRemoteSendCommand =
        @convention(c) (Int32, UnsafeRawPointer?) -> UInt8

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        setupArtworkBackground()
        setupWebClock()
        setupErrorLabel()
        setupMediaRemote()
        setupMediaControls()
        startBridgeArtworkUpdates()

        UIApplication.shared.isIdleTimerDisabled = true
        loadClock()
    }

    private func setupArtworkBackground() {
        artworkView = UIImageView()
        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.backgroundColor = .black
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true

        view.addSubview(artworkView)

        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            artworkView.topAnchor.constraint(equalTo: view.topAnchor),
            artworkView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

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
            guard let self else { return }

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
            <style id="native-artwork-background">
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

    // MARK: - Mac artwork bridge

    private func startBridgeArtworkUpdates() {
        refreshBridgeArtwork()

        bridgeTimer = Timer.scheduledTimer(
            withTimeInterval: 1.5,
            repeats: true
        ) { [weak self] _ in
            self?.refreshBridgeArtwork()
        }
    }

    private func refreshBridgeArtwork() {
        guard !bridgeStatusRequestInFlight else {
            return
        }

        bridgeStatusRequestInFlight = true

        var request = URLRequest(
            url: bridgeBaseURL.appendingPathComponent("status"),
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 2.5
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        bridgeSession.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }

            DispatchQueue.main.async {
                self.bridgeStatusRequestInFlight = false
            }

            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let data,
                let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else {
                return
            }

            let hasArtwork = json["hasArtwork"] as? Bool ?? false
            let artworkHash = json["artworkSHA256"] as? String

            guard
                hasArtwork,
                let artworkHash,
                !artworkHash.isEmpty
            else {
                return
            }

            DispatchQueue.main.async {
                guard artworkHash != self.lastBridgeArtworkHash else {
                    return
                }

                self.fetchBridgeArtwork(expectedHash: artworkHash)
            }
        }.resume()
    }

    private func fetchBridgeArtwork(expectedHash: String) {
        guard !bridgeArtworkRequestInFlight else {
            return
        }

        bridgeArtworkRequestInFlight = true

        var components = URLComponents(
            url: bridgeBaseURL.appendingPathComponent("artwork"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "v", value: expectedHash)
        ]

        var request = URLRequest(
            url: components.url!,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 4.0
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        bridgeSession.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }

            DispatchQueue.main.async {
                self.bridgeArtworkRequestInFlight = false
            }

            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let data,
                let image = UIImage(data: data)
            else {
                return
            }

            DispatchQueue.main.async {
                self.lastBridgeArtworkHash = expectedHash
                self.artworkView.image = image
                self.artworkView.backgroundColor = .black
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
        bridgeTimer?.invalidate()
        bridgeSession.invalidateAndCancel()
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
