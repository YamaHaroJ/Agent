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
    private var webView: WKWebView!
    private var errorLabel: UILabel!

    private var mediaControls: UIVisualEffectView!
    private var playPauseButton: UIButton!
    private var volumeView: MPVolumeView!

    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var mediaRemoteSendCommand: MRMediaRemoteSendCommand?

    // Private MediaRemote function:
    // Boolean MRMediaRemoteSendCommand(MRMediaRemoteCommand command, id userInfo)
    // Command 2 = TogglePlayPause.
    private typealias MRMediaRemoteSendCommand =
        @convention(c) (Int32, UnsafeRawPointer?) -> UInt8

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
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
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30)
        ])

        setupMediaRemote()
        setupMediaControls()

        UIApplication.shared.isIdleTimerDisabled = true
        loadClock()
    }

    private func loadClock() {
        let sourceURL = URL(
            string: "https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/index.html"
        )!

        URLSession.shared.dataTask(with: sourceURL) { [weak self] data, _, error in
            guard let self else { return }

            guard
                let data,
                let html = String(data: data, encoding: .utf8)
            else {
                DispatchQueue.main.async {
                    self.errorLabel.text =
                        "Clock could not load.\n\n" +
                        (error?.localizedDescription ?? "Unknown network error")
                    self.errorLabel.isHidden = false
                }
                return
            }

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

    private func setupMediaRemote() {
        let frameworkPath =
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            return
        }

        mediaRemoteHandle = handle

        guard let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else {
            return
        }

        mediaRemoteSendCommand = unsafeBitCast(
            symbol,
            to: MRMediaRemoteSendCommand.self
        )
    }

    private func setupMediaControls() {
        mediaControls = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemThinMaterialDark)
        )
        mediaControls.translatesAutoresizingMaskIntoConstraints = false
        mediaControls.layer.cornerRadius = 26
        mediaControls.clipsToBounds = true

        playPauseButton = UIButton(type: .system)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.tintColor = .white
        playPauseButton.setImage(
            UIImage(systemName: "playpause.fill"),
            for: .normal
        )
        playPauseButton.addTarget(
            self,
            action: #selector(toggleExternalPlayback),
            for: .touchUpInside
        )

        volumeView = MPVolumeView(frame: .zero)
        volumeView.translatesAutoresizingMaskIntoConstraints = false
        volumeView.showsVolumeSlider = true
        volumeView.showsRouteButton = false
        volumeView.tintColor = .white

        mediaControls.contentView.addSubview(playPauseButton)
        mediaControls.contentView.addSubview(volumeView)
        view.addSubview(mediaControls)

        NSLayoutConstraint.activate([
            mediaControls.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 18
            ),
            mediaControls.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -18
            ),
            mediaControls.widthAnchor.constraint(equalToConstant: 285),
            mediaControls.heightAnchor.constraint(equalToConstant: 52),

            playPauseButton.leadingAnchor.constraint(
                equalTo: mediaControls.contentView.leadingAnchor,
                constant: 10
            ),
            playPauseButton.centerYAnchor.constraint(
                equalTo: mediaControls.contentView.centerYAnchor
            ),
            playPauseButton.widthAnchor.constraint(equalToConstant: 42),
            playPauseButton.heightAnchor.constraint(equalToConstant: 42),

            volumeView.leadingAnchor.constraint(
                equalTo: playPauseButton.trailingAnchor,
                constant: 8
            ),
            volumeView.trailingAnchor.constraint(
                equalTo: mediaControls.contentView.trailingAnchor,
                constant: -14
            ),
            volumeView.centerYAnchor.constraint(
                equalTo: mediaControls.contentView.centerYAnchor
            ),
            volumeView.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    @objc private func toggleExternalPlayback() {
        guard let sendCommand = mediaRemoteSendCommand else {
            showMediaControlUnavailable()
            return
        }

        let accepted = sendCommand(2, nil)

        guard accepted != 0 else {
            showMediaControlUnavailable()
            return
        }

        UIView.animate(
            withDuration: 0.08,
            animations: {
                self.playPauseButton.transform =
                    CGAffineTransform(scaleX: 0.82, y: 0.82)
            },
            completion: { _ in
                UIView.animate(withDuration: 0.10) {
                    self.playPauseButton.transform = .identity
                }
            }
        )
    }

    private func showMediaControlUnavailable() {
        guard presentedViewController == nil else { return }

        let alert = UIAlertController(
            title: "Play/Pause unavailable",
            message:
                "This iPad blocked direct control of another app's playback. " +
                "The volume slider will still work normally.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default))
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
        if let url = navigationAction.request.url,
           url.host?.contains("soundcloud.com") == true {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}
