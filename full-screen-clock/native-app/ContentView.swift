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
    private var artworkView: UIImageView!
    private var webView: WKWebView!
    private var errorLabel: UILabel!
    private var artworkDebugLabel: UILabel!

    private var mediaControls: UIVisualEffectView!
    private var previousButton: UIButton!
    private var playPauseButton: UIButton!
    private var nextButton: UIButton!
    private var volumeView: MPVolumeView!

    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var mediaRemoteSendCommand: MRMediaRemoteSendCommand?
    private var mediaRemoteGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfo?
    private var mediaRemoteGetNowPlayingInfoWithArtwork: MRMediaRemoteGetNowPlayingInfoWithOptionalArtwork?
    private var mediaRemoteRegisterForNotifications: MRMediaRemoteRegisterForNowPlayingNotifications?
    private var mediaRemoteSetWantsNotifications: MRMediaRemoteSetWantsNowPlayingNotifications?
    private var mediaRemoteGetActiveOrigin: MRMediaRemoteGetOrigin?
    private var mediaRemoteGetActivePlayerPathsForOrigin: MRMediaRemoteGetObjectsForOrigin?
    private var mediaRemoteGetNowPlayingInfoForPlayer: MRMediaRemoteGetNowPlayingInfoForPlayer?
    private var mediaRemoteCopyArtworkData: MRNowPlayingArtworkCopyImageData?
    private var artworkTimer: Timer?
    private var lastArtworkData: Data?
    private var lastArtworkLookupKey: String?
    private var artworkLookupInFlight = false

    private typealias MRMediaRemoteSendCommand =
        @convention(c) (Int32, UnsafeRawPointer?) -> UInt8

    private typealias MRMediaRemoteGetNowPlayingInfo =
        @convention(c) (
            DispatchQueue,
            @escaping @convention(block) ([String: Any]) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingInfoWithOptionalArtwork =
        @convention(c) (
            UnsafeRawPointer?,
            UnsafeRawPointer?,
            DispatchQueue,
            @escaping @convention(block) (NSDictionary?, NSData?) -> Void
        ) -> Void

    private typealias MRMediaRemoteRegisterForNowPlayingNotifications =
        @convention(c) (DispatchQueue) -> Void

    private typealias MRMediaRemoteSetWantsNowPlayingNotifications =
        @convention(c) (Bool) -> Void

    private typealias MRMediaRemoteGetOrigin =
        @convention(c) (
            DispatchQueue,
            @escaping @convention(block) (Bool, AnyObject?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetObjectsForOrigin =
        @convention(c) (
            AnyObject,
            DispatchQueue,
            @escaping @convention(block) (NSArray?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingInfoForPlayer =
        @convention(c) (
            AnyObject,
            Bool,
            DispatchQueue,
            @escaping @convention(block) (NSDictionary?, UnsafeRawPointer?) -> Void
        ) -> Void

    private typealias MRNowPlayingArtworkCopyImageData =
        @convention(c) (UnsafeRawPointer) -> Unmanaged<CFData>?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

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

        artworkDebugLabel = UILabel()
        artworkDebugLabel.translatesAutoresizingMaskIntoConstraints = false
        artworkDebugLabel.textColor = .systemYellow
        artworkDebugLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        artworkDebugLabel.numberOfLines = 0
        artworkDebugLabel.textAlignment = .left
        artworkDebugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        artworkDebugLabel.layer.cornerRadius = 8
        artworkDebugLabel.clipsToBounds = true
        artworkDebugLabel.text = "ART DEBUG: starting..."
        view.addSubview(artworkDebugLabel)

        NSLayoutConstraint.activate([
            artworkDebugLabel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 18
            ),
            artworkDebugLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 18
            ),
            artworkDebugLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 510)
        ])

        setupMediaRemote()
        setupMediaControls()
        startArtworkUpdates()

        UIApplication.shared.isIdleTimerDisabled = true
        loadClock()
    }

    private func loadClock() {
        var components = URLComponents(
            string: "https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/index.html"
        )!
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))
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

    private func setArtworkDebug(_ text: String) {
        DispatchQueue.main.async {
            guard self.artworkView.image == nil else {
                self.artworkDebugLabel.isHidden = true
                return
            }
            self.artworkDebugLabel.isHidden = false
            self.artworkDebugLabel.text = "ART DEBUG\n" + text
        }
    }

    private func setupMediaRemote() {
        let frameworkPath =
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            setArtworkDebug("MediaRemote failed to load")
            return
        }

        mediaRemoteHandle = handle

        if let commandSymbol = dlsym(handle, "MRMediaRemoteSendCommand") {
            mediaRemoteSendCommand = unsafeBitCast(
                commandSymbol,
                to: MRMediaRemoteSendCommand.self
            )
        }

        if let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            mediaRemoteGetNowPlayingInfo = unsafeBitCast(
                infoSymbol,
                to: MRMediaRemoteGetNowPlayingInfo.self
            )
        }

        if let artworkInfoSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingInfoWithOptionalArtwork"
        ) {
            mediaRemoteGetNowPlayingInfoWithArtwork = unsafeBitCast(
                artworkInfoSymbol,
                to: MRMediaRemoteGetNowPlayingInfoWithOptionalArtwork.self
            )
        }

        setArtworkDebug(
            "MediaRemote loaded\n" +
            "legacyInfo: \(mediaRemoteGetNowPlayingInfo != nil)\n" +
            "optionalArtwork: \(mediaRemoteGetNowPlayingInfoWithArtwork != nil)"
        )

        if let registerSymbol = dlsym(
            handle,
            "MRMediaRemoteRegisterForNowPlayingNotifications"
        ) {
            mediaRemoteRegisterForNotifications = unsafeBitCast(
                registerSymbol,
                to: MRMediaRemoteRegisterForNowPlayingNotifications.self
            )
            mediaRemoteRegisterForNotifications?(DispatchQueue.main)
        }

        if let wantsSymbol = dlsym(
            handle,
            "MRMediaRemoteSetWantsNowPlayingNotifications"
        ) {
            mediaRemoteSetWantsNotifications = unsafeBitCast(
                wantsSymbol,
                to: MRMediaRemoteSetWantsNowPlayingNotifications.self
            )
            mediaRemoteSetWantsNotifications?(true)
        }

        if let activeOriginSymbol = dlsym(
            handle,
            "MRMediaRemoteGetActiveOrigin"
        ) {
            mediaRemoteGetActiveOrigin = unsafeBitCast(
                activeOriginSymbol,
                to: MRMediaRemoteGetOrigin.self
            )
        }

        if let playerPathsSymbol = dlsym(
            handle,
            "MRMediaRemoteGetActivePlayerPathsForOrigin"
        ) {
            mediaRemoteGetActivePlayerPathsForOrigin = unsafeBitCast(
                playerPathsSymbol,
                to: MRMediaRemoteGetObjectsForOrigin.self
            )
        }

        if let playerInfoSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingInfoForPlayer"
        ) {
            mediaRemoteGetNowPlayingInfoForPlayer = unsafeBitCast(
                playerInfoSymbol,
                to: MRMediaRemoteGetNowPlayingInfoForPlayer.self
            )
        }

        if let artworkCopySymbol = dlsym(
            handle,
            "MRNowPlayingArtworkCopyImageData"
        ) {
            mediaRemoteCopyArtworkData = unsafeBitCast(
                artworkCopySymbol,
                to: MRNowPlayingArtworkCopyImageData.self
            )
        }

        setArtworkDebug(
            "MediaRemote loaded\n" +
            "global info: \(mediaRemoteGetNowPlayingInfo != nil)\n" +
            "active origin: \(mediaRemoteGetActiveOrigin != nil)\n" +
            "player paths: \(mediaRemoteGetActivePlayerPathsForOrigin != nil)\n" +
            "player info: \(mediaRemoteGetNowPlayingInfoForPlayer != nil)"
        )
    }

    private func startArtworkUpdates() {
        refreshArtwork()

        artworkTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            self?.refreshArtwork()
        }
    }

    private func refreshArtwork() {
        // First try the active-origin/player-path route used by modern
        // MediaRemote. The legacy global info API can return an empty
        // dictionary even while Control Center has full metadata.
        if tryArtworkFromActivePlayerPath() {
            return
        }

        refreshArtworkFromLegacyAPIs()
    }

    @discardableResult
    private func tryArtworkFromActivePlayerPath() -> Bool {
        guard
            let getActiveOrigin = mediaRemoteGetActiveOrigin,
            let getPlayerPaths = mediaRemoteGetActivePlayerPathsForOrigin,
            let getPlayerInfo = mediaRemoteGetNowPlayingInfoForPlayer
        else {
            return false
        }

        getActiveOrigin(DispatchQueue.main) { [weak self] success, origin in
            guard let self else { return }

            guard success, let origin else {
                self.setArtworkDebug("Active origin unavailable")
                self.refreshArtworkFromLegacyAPIs()
                return
            }

            getPlayerPaths(origin, DispatchQueue.main) { [weak self] paths in
                guard let self else { return }

                guard
                    let paths,
                    let playerPath = paths.firstObject as AnyObject?
                else {
                    self.setArtworkDebug("Active origin found, but no active player path")
                    self.refreshArtworkFromLegacyAPIs()
                    return
                }

                getPlayerInfo(
                    playerPath,
                    true,
                    DispatchQueue.main
                ) { [weak self] infoObject, artworkObject in
                    guard let self else { return }

                    let info = infoObject as? [String: Any] ?? [:]
                    let title =
                        info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
                        ?? "<nil>"
                    let artist =
                        info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
                        ?? "<nil>"

                    var artworkData =
                        info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

                    if artworkData == nil,
                       let artworkObject,
                       let copied =
                            self.mediaRemoteCopyArtworkData?(artworkObject) {
                        artworkData = copied.takeRetainedValue() as Data
                    }

                    self.setArtworkDebug(
                        "PLAYER PATH CALLBACK\n" +
                        "paths: \(paths.count)\n" +
                        "keys: \(info.count)\n" +
                        "title: \(title)\n" +
                        "artist: \(artist)\n" +
                        "artwork bytes: \(artworkData?.count ?? 0)"
                    )

                    if let artworkData,
                       let image = UIImage(data: artworkData) {
                        self.lastArtworkLookupKey = nil
                        self.setArtwork(image, data: artworkData)
                        return
                    }

                    self.processArtworkMetadataFallback(info)
                }
            }
        }

        return true
    }

    private func refreshArtworkFromLegacyAPIs() {
        if let getNowPlayingInfoWithArtwork =
            mediaRemoteGetNowPlayingInfoWithArtwork {
            getNowPlayingInfoWithArtwork(
                nil,
                nil,
                DispatchQueue.main
            ) { [weak self] infoObject, artworkObject in
                guard let self else { return }

                let info = infoObject as? [String: Any] ?? [:]

                if let data = artworkObject as Data?,
                   let image = UIImage(data: data) {
                    self.lastArtworkLookupKey = nil
                    self.setArtwork(image, data: data)
                    return
                }

                if let data =
                    info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
                   let image = UIImage(data: data) {
                    self.lastArtworkLookupKey = nil
                    self.setArtwork(image, data: data)
                    return
                }

                self.processArtworkMetadataFallback(info)
            }
            return
        }

        guard let getNowPlayingInfo = mediaRemoteGetNowPlayingInfo else {
            setArtworkDebug("No usable MediaRemote metadata reader")
            return
        }

        getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            self?.processArtworkMetadataFallback(info)
        }
    }

    private func processArtworkMetadataFallback(
        _ info: [String: Any]
    ) {
        var artworkData =
            info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

        if artworkData == nil {
            for value in info.values {
                if let data = value as? Data,
                   UIImage(data: data) != nil {
                    artworkData = data
                    break
                }
            }
        }

        if let artworkData,
           let image = UIImage(data: artworkData) {
            lastArtworkLookupKey = nil
            setArtwork(image, data: artworkData)
            return
        }

        let title =
            info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let artist =
            info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        let album =
            info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String

        fetchArtworkFallback(
            title: title,
            artist: artist,
            album: album
        )
    }

    private func fetchArtworkFallback(
        title: String?,
        artist: String?,
        album: String?
    ) {
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanAlbum = album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !cleanTitle.isEmpty || !cleanArtist.isEmpty else {
            setArtworkDebug("No title/artist metadata available for web fallback")
            return
        }

        let lookupKey = "\(cleanTitle)|\(cleanArtist)|\(cleanAlbum)"
            .lowercased()

        guard lookupKey != lastArtworkLookupKey || artworkView.image == nil else {
            return
        }

        guard !artworkLookupInFlight else {
            return
        }

        artworkLookupInFlight = true
        lastArtworkLookupKey = lookupKey
        setArtworkDebug(
            "No direct artwork\nSearching Apple catalog for:\n\(cleanArtist) — \(cleanTitle)"
        )

        var components = URLComponents(
            string: "https://itunes.apple.com/search"
        )!

        let term = [cleanArtist, cleanTitle]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10")
        ]

        guard let url = components.url else {
            artworkLookupInFlight = false
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }

            defer {
                DispatchQueue.main.async {
                    self.artworkLookupInFlight = false
                }
            }

            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                let results = json["results"] as? [[String: Any]],
                !results.isEmpty
            else {
                self.setArtworkDebug("Apple catalog fallback returned no results")
                return
            }

            self.setArtworkDebug(
                "Apple catalog returned \(results.count) result(s)\nDownloading best artwork..."
            )

            func normalized(_ value: String?) -> String {
                (value ?? "")
                    .lowercased()
                    .replacingOccurrences(
                        of: "[^a-z0-9]+",
                        with: " ",
                        options: .regularExpression
                    )
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let targetTitle = normalized(cleanTitle)
            let targetArtist = normalized(cleanArtist)

            let best = results.max { lhs, rhs in
                func score(_ item: [String: Any]) -> Int {
                    let itemTitle = normalized(item["trackName"] as? String)
                    let itemArtist = normalized(item["artistName"] as? String)
                    let itemAlbum = normalized(item["collectionName"] as? String)

                    var value = 0
                    if !targetTitle.isEmpty && itemTitle == targetTitle {
                        value += 8
                    } else if !targetTitle.isEmpty &&
                                (itemTitle.contains(targetTitle) ||
                                 targetTitle.contains(itemTitle)) {
                        value += 4
                    }

                    if !targetArtist.isEmpty && itemArtist == targetArtist {
                        value += 6
                    } else if !targetArtist.isEmpty &&
                                (itemArtist.contains(targetArtist) ||
                                 targetArtist.contains(itemArtist)) {
                        value += 3
                    }

                    if !cleanAlbum.isEmpty &&
                       itemAlbum == normalized(cleanAlbum) {
                        value += 2
                    }

                    return value
                }

                return score(lhs) < score(rhs)
            }

            guard
                let artworkString =
                    best?["artworkUrl100"] as? String
            else {
                return
            }

            let largeArtworkString = artworkString
                .replacingOccurrences(
                    of: "100x100bb",
                    with: "1200x1200bb"
                )

            guard let artworkURL = URL(string: largeArtworkString) else {
                return
            }

            var request = URLRequest(
                url: artworkURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 20
            )
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

            URLSession.shared.dataTask(with: request) { [weak self] imageData, _, _ in
                guard
                    let self,
                    let imageData,
                    let image = UIImage(data: imageData)
                else {
                    return
                }

                self.setArtworkDebug(
                    "Artwork downloaded: \(imageData.count) bytes"
                )
                self.setArtwork(image, data: imageData)
            }.resume()
        }.resume()
    }

    private func setArtwork(_ image: UIImage?, data: Data?) {
        DispatchQueue.main.async {
            if let data, self.lastArtworkData == data {
                return
            }

            self.lastArtworkData = data
            self.artworkDebugLabel.isHidden = image != nil

            UIView.transition(
                with: self.artworkView,
                duration: 0.22,
                options: [.transitionCrossDissolve, .allowAnimatedContent],
                animations: {
                    self.artworkView.image = image
                    self.artworkView.backgroundColor =
                        image == nil ? .black : .clear
                }
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
            arrangedSubviews: [previousButton, playPauseButton, nextButton]
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
        button.addTarget(self, action: action, for: .touchUpInside)
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

    private func sendMediaCommand(_ command: Int32, button: UIButton) {
        guard let sendCommand = mediaRemoteSendCommand else {
            showMediaControlUnavailable()
            return
        }

        let accepted = sendCommand(command, nil)

        guard accepted != 0 else {
            showMediaControlUnavailable()
            return
        }

        refreshArtwork()

        UIView.animate(
            withDuration: 0.08,
            animations: {
                button.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
            },
            completion: { _ in
                UIView.animate(withDuration: 0.10) {
                    button.transform = .identity
                }
            }
        )
    }

    private func showMediaControlUnavailable() {
        guard presentedViewController == nil else { return }

        let alert = UIAlertController(
            title: "Media control unavailable",
            message:
                "This iPad blocked direct control of the current media app. " +
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
        artworkTimer?.invalidate()
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
