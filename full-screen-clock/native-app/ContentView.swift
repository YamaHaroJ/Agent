import SwiftUI
import WebKit
import UIKit
import MediaPlayer
import Darwin
import ObjectiveC

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
    private var mediaRemoteGetLocalOrigin: MRMediaRemoteGetLocalOrigin?
    private var mediaRemoteGetNowPlayingArtwork: MRMediaRemoteGetNowPlayingArtwork?
    private var mediaRemoteGetNowPlayingClient: MRMediaRemoteGetNowPlayingClient?
    private var mediaRemoteGetNowPlayingClients: MRMediaRemoteGetNowPlayingClients?
    private var mediaRemoteGetClientForOrigin: MRMediaRemoteGetNowPlayingClientForOrigin?
    private var mediaRemoteGetPlayerForClient: MRMediaRemoteGetNowPlayingPlayerForClient?
    private var mediaRemoteGetInfoForPlayerSimple: MRMediaRemoteGetNowPlayingInfoForPlayerSimple?
    private var mediaRemoteGetInfoForClient: MRMediaRemoteGetNowPlayingInfoForClient?
    private var mediaRemoteGetAppDisplayID: MRMediaRemoteGetNowPlayingApplicationDisplayID?
    private var mediaRemoteGetInfoForApp: MRMediaRemoteGetNowPlayingInfoForApp?
    private var mediaRemoteClientBundleID: MRNowPlayingClientGetBundleIdentifier?
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

    private var mediaControlsHandle: UnsafeMutableRawPointer?
    private var mediaControlsEndpoint: NSObject?
    private var mediaControlsNowPlayingController: NSObject?
    private var mediaControlsMetadataController: NSObject?
    private var mediaControlsArtworkCatalog: NSObject?
    private var mediaControlsArtworkRequestKey: String?
    private var mediaControlsArtworkRequestInFlight = false

    private var systemMediaModuleProvider: NSObject?
    private var systemMediaModuleViewController: UIViewController?

    private typealias MRMediaRemoteSendCommand =
        @convention(c) (Int32, UnsafeRawPointer?) -> UInt8

    private typealias MRMediaRemoteGetLocalOrigin =
        @convention(c) () -> UnsafeRawPointer?

    private typealias MRMediaRemoteGetNowPlayingArtwork =
        @convention(c) (
            UnsafeRawPointer?,
            DispatchQueue,
            @escaping @convention(block) (UnsafeRawPointer?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingClient =
        @convention(c) (
            DispatchQueue,
            @escaping @convention(block) (AnyObject?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingClientForOrigin =
        @convention(c) (
            UnsafeRawPointer?,
            DispatchQueue,
            @escaping @convention(block) (AnyObject?, AnyObject?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingClients =
        @convention(c) (
            DispatchQueue,
            @escaping @convention(block) (NSArray?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingPlayerForClient =
        @convention(c) (
            AnyObject,
            UnsafeRawPointer?,
            DispatchQueue,
            @escaping @convention(block) (AnyObject?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingInfoForPlayerSimple =
        @convention(c) (
            AnyObject,
            Bool,
            DispatchQueue,
            @escaping @convention(block) (NSDictionary?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingInfoForClient =
        @convention(c) (
            AnyObject,
            UnsafeRawPointer?,
            Bool,
            DispatchQueue,
            @escaping @convention(block) (NSDictionary?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingApplicationDisplayID =
        @convention(c) (
            DispatchQueue,
            @escaping @convention(block) (CFString?) -> Void
        ) -> Void

    private typealias MRMediaRemoteGetNowPlayingInfoForApp =
        @convention(c) (
            CFString,
            UnsafeRawPointer?,
            Bool,
            DispatchQueue,
            @escaping @convention(block) (NSDictionary?) -> Void
        ) -> Void

    private typealias MRNowPlayingClientGetBundleIdentifier =
        @convention(c) (AnyObject) -> Unmanaged<CFString>?

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
        setupSystemMediaControlsBridge()
        setupEmbeddedSystemMediaModule()
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

    private func setupEmbeddedSystemMediaModule() {
        guard
            let provider = systemClassObject(
                "MRUMediaModuleProvider",
                selectorName: "sharedProvider"
            )
        else {
            setArtworkDebug("SYSTEM MODULE: provider unavailable")
            return
        }

        let rootSelector = NSSelectorFromString("rootViewController")
        guard
            provider.responds(to: rootSelector),
            let root = provider
                .perform(rootSelector)?
                .takeUnretainedValue() as? UIViewController
        else {
            setArtworkDebug("SYSTEM MODULE: root view controller unavailable")
            return
        }

        systemMediaModuleProvider = provider
        systemMediaModuleViewController = root

        addChild(root)

        let moduleView = root.view!
        moduleView.frame = CGRect(
            x: -5000,
            y: -5000,
            width: 500,
            height: 500
        )
        moduleView.alpha = 0.01
        moduleView.isUserInteractionEnabled = false
        view.insertSubview(moduleView, at: 0)

        root.didMove(toParent: self)
        root.view.setNeedsLayout()
        root.view.layoutIfNeeded()

        setArtworkDebug(
            "SYSTEM MODULE embedded\n" +
            "Waiting for its Now Playing session..."
        )
    }

    private func findView(
        in root: UIView,
        classNames: Set<String>
    ) -> UIView? {
        if classNames.contains(NSStringFromClass(type(of: root))) {
            return root
        }

        for child in root.subviews {
            if let match = findView(in: child, classNames: classNames) {
                return match
            }
        }

        return nil
    }

    private func objectIvar(
        _ object: AnyObject,
        named name: String
    ) -> AnyObject? {
        var currentClass: AnyClass? = object_getClass(object)

        while let cls = currentClass {
            if let ivar = class_getInstanceVariable(cls, name) {
                return object_getIvar(object, ivar) as AnyObject?
            }
            currentClass = class_getSuperclass(cls)
        }

        return nil
    }

    @discardableResult
    private func refreshArtworkFromEmbeddedSystemModule() -> Bool {
        guard let root = systemMediaModuleViewController?.view else {
            return false
        }

        root.setNeedsLayout()
        root.layoutIfNeeded()

        let nowPlayingNames: Set<String> = [
            "_TtC13MediaControls33MediaControlsModuleNowPlayingView",
            "MRUMediaControlsModuleNowPlayingView"
        ]

        guard let nowPlayingView = findView(
            in: root,
            classNames: nowPlayingNames
        ) else {
            var imageViewCount = 0
            var largestImagePixels = 0.0

            func inspect(_ view: UIView) {
                if let imageView = view as? UIImageView,
                   let image = imageView.image {
                    imageViewCount += 1
                    let pixels =
                        image.size.width * image.scale *
                        image.size.height * image.scale
                    largestImagePixels = max(largestImagePixels, pixels)
                }

                for child in view.subviews {
                    inspect(child)
                }
            }

            inspect(root)

            setArtworkDebug(
                "SYSTEM MODULE active\n" +
                "Now Playing view: NOT FOUND\n" +
                "image views with images: \(imageViewCount)\n" +
                "largest image pixels: \(Int(largestImagePixels))"
            )
            return true
        }

        if let image =
            objectIvar(nowPlayingView, named: "artworkImage") as? UIImage {
            if let data = image.jpegData(compressionQuality: 0.98) {
                setArtwork(image, data: data)
            } else {
                setArtwork(image, data: nil)
            }
            return true
        }

        let artworkControlNames: Set<String> = [
            "_TtC13MediaControls14ArtworkControl",
            "MRUArtworkView"
        ]

        if let artworkControl = findView(
            in: nowPlayingView,
            classNames: artworkControlNames
        ) {
            if let artworkView =
                objectIvar(artworkControl, named: "artworkView") as? UIView {
                if let imageView =
                    objectIvar(artworkView, named: "imageView") as? UIImageView,
                   let image = imageView.image {
                    if let data =
                        image.jpegData(compressionQuality: 0.98) {
                        setArtwork(image, data: data)
                    } else {
                        setArtwork(image, data: nil)
                    }
                    return true
                }

                if let imageView = artworkView as? UIImageView,
                   let image = imageView.image {
                    if let data =
                        image.jpegData(compressionQuality: 0.98) {
                        setArtwork(image, data: data)
                    } else {
                        setArtwork(image, data: nil)
                    }
                    return true
                }
            }
        }

        var candidates: [(UIImage, Int)] = []

        func collectImages(_ view: UIView) {
            if let imageView = view as? UIImageView,
               let image = imageView.image {
                let width = Int(image.size.width * image.scale)
                let height = Int(image.size.height * image.scale)
                if width >= 100 && height >= 100 {
                    candidates.append((image, width * height))
                }
            }

            for child in view.subviews {
                collectImages(child)
            }
        }

        collectImages(nowPlayingView)

        if let best = candidates.max(by: { $0.1 < $1.1 }) {
            if let data = best.0.jpegData(compressionQuality: 0.98) {
                setArtwork(best.0, data: data)
            } else {
                setArtwork(best.0, data: nil)
            }
            return true
        }

        setArtworkDebug(
            "SYSTEM MODULE active\n" +
            "Now Playing view: FOUND\n" +
            "artworkImage ivar: EMPTY\n" +
            "large image candidates: \(candidates.count)"
        )
        return true
    }

    @objc(nowPlayingControllerShouldAutomaticallyUpdateResponse:)
    private func nowPlayingControllerShouldAutomaticallyUpdateResponse(
        _ controller: AnyObject
    ) -> Bool {
        true
    }

    @objc(nowPlayingController:metadataController:didChangeArtwork:)
    private func mediaControlsArtworkChanged(
        _ controller: AnyObject,
        metadataController: AnyObject,
        artwork: AnyObject
    ) {
        DispatchQueue.main.async { [weak self] in
            _ = self?.refreshArtworkFromSystemMediaControls()
        }
    }

    @objc(nowPlayingController:metadataController:didChangeNowPlayingInfo:)
    private func mediaControlsInfoChanged(
        _ controller: AnyObject,
        metadataController: AnyObject,
        info: AnyObject
    ) {
        DispatchQueue.main.async { [weak self] in
            _ = self?.refreshArtworkFromSystemMediaControls()
        }
    }

    private func systemClassObject(
        _ className: String,
        selectorName: String
    ) -> NSObject? {
        guard let cls = NSClassFromString(className) else {
            return nil
        }

        let classObject: AnyObject = cls as AnyObject
        let selector = NSSelectorFromString(selectorName)

        guard classObject.responds(to: selector) else {
            return nil
        }

        return classObject
            .perform(selector)?
            .takeUnretainedValue() as? NSObject
    }

    private func systemAllocInit(
        _ className: String,
        selectorName: String,
        argument: NSObject
    ) -> NSObject? {
        guard let cls = NSClassFromString(className) else {
            return nil
        }

        let classObject: AnyObject = cls as AnyObject
        let allocSelector = NSSelectorFromString("alloc")
        let initSelector = NSSelectorFromString(selectorName)

        guard
            let allocated = classObject
                .perform(allocSelector)?
                .takeUnretainedValue() as? NSObject,
            allocated.responds(to: initSelector)
        else {
            return nil
        }

        return allocated
            .perform(initSelector, with: argument)?
            .takeUnretainedValue() as? NSObject
    }

    private func setupSystemMediaControlsBridge() {
        let frameworkPath =
            "/System/Library/PrivateFrameworks/MediaControls.framework/MediaControls"

        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            setArtworkDebug("MEDIA CONTROLS: framework failed to load")
            return
        }

        mediaControlsHandle = handle

        guard let endpoint = systemClassObject(
            "MRUEndpointController",
            selectorName: "proactiveEndpointController"
        ) else {
            setArtworkDebug("MEDIA CONTROLS: proactive endpoint unavailable")
            return
        }

        guard let controller = systemAllocInit(
            "MRUNowPlayingController",
            selectorName: "initWithEndpointController:",
            argument: endpoint
        ) else {
            setArtworkDebug("MEDIA CONTROLS: now-playing controller failed")
            return
        }

        mediaControlsEndpoint = endpoint
        mediaControlsNowPlayingController = controller

        let addObserverSelector = NSSelectorFromString("addObserver:")
        if controller.responds(to: addObserverSelector) {
            _ = controller.perform(addObserverSelector, with: self)
        }

        let updateSelector =
            NSSelectorFromString("updateAutomaticResponseLoading")
        if controller.responds(to: updateSelector) {
            _ = controller.perform(updateSelector)
        }

        let metadataSelector = NSSelectorFromString("metadataController")
        if controller.responds(to: metadataSelector) {
            mediaControlsMetadataController = controller
                .perform(metadataSelector)?
                .takeUnretainedValue() as? NSObject
        }

        // Mirror what Apple's own MRUNowPlayingController does when its
        // controls are visible: allow its endpoint response to stay live.
        if let innerEndpoint =
            endpoint.value(forKey: "endpointController") as? NSObject {
            innerEndpoint.setValue(true, forKey: "allowsAutomaticResponseLoading")
            innerEndpoint.setValue(true, forKey: "onScreen")
            innerEndpoint.setValue(true, forKey: "deviceUnlocked")

            if let proxy =
                innerEndpoint.value(forKey: "proxyDelegate") as? NSObject {
                let beginSelector = NSSelectorFromString("beginObserving")
                if proxy.responds(to: beginSelector) {
                    _ = proxy.perform(beginSelector)
                }
            }
        }

        if mediaControlsMetadataController != nil {
            setArtworkDebug(
                "MEDIA CONTROLS bridge active\n" +
                "Waiting for Control Center metadata..."
            )
        } else {
            setArtworkDebug(
                "MEDIA CONTROLS loaded, but metadata controller is unavailable"
            )
        }
    }

    @discardableResult
    private func refreshArtworkFromSystemMediaControls() -> Bool {
        guard let metadata = mediaControlsMetadataController else {
            return false
        }

        let info =
            metadata.value(forKey: "nowPlayingInfo") as? NSObject
        let title =
            info?.value(forKey: "title") as? String ?? "<nil>"
        let artist =
            info?.value(forKey: "artist") as? String ?? "<nil>"
        let album =
            info?.value(forKey: "album") as? String ?? "<nil>"
        let bundleID =
            metadata.value(forKey: "bundleID") as? String ?? "<nil>"
        let artwork =
            metadata.value(forKey: "artwork") as? NSObject

        setArtworkDebug(
            "MEDIA CONTROLS\n" +
            "bundle: \(bundleID)\n" +
            "title: \(title)\n" +
            "artist: \(artist)\n" +
            "album: \(album)\n" +
            "artwork object: \(artwork == nil ? "NO" : "YES")"
        )

        guard let artwork else {
            return true
        }

        guard let catalog =
            artwork.value(forKey: "catalog") as? NSObject
        else {
            setArtworkDebug(
                "MEDIA CONTROLS\n" +
                "title: \(title)\n" +
                "artwork object: YES\n" +
                "artwork catalog: NO"
            )
            return true
        }

        mediaControlsArtworkCatalog = catalog

        let diskSelector = NSSelectorFromString("bestImageFromDisk")
        if catalog.responds(to: diskSelector),
           let image = catalog
                .perform(diskSelector)?
                .takeUnretainedValue() as? UIImage {
            if let imageData = image.jpegData(compressionQuality: 0.98) {
                setArtwork(image, data: imageData)
            } else {
                setArtwork(image, data: nil)
            }
            return true
        }

        let requestKey =
            "\(bundleID)|\(title)|\(artist)|\(album)|\(ObjectIdentifier(catalog))"

        guard
            !mediaControlsArtworkRequestInFlight ||
            mediaControlsArtworkRequestKey != requestKey
        else {
            return true
        }

        mediaControlsArtworkRequestKey = requestKey
        mediaControlsArtworkRequestInFlight = true

        let sizeSelector = NSSelectorFromString("setFittingSize:")
        if catalog.responds(to: sizeSelector) {
            typealias SetFittingSizeFunction =
                @convention(c) (
                    AnyObject,
                    Selector,
                    CGSize
                ) -> Void

            let function = unsafeBitCast(
                catalog.method(for: sizeSelector),
                to: SetFittingSizeFunction.self
            )

            function(
                catalog,
                sizeSelector,
                CGSize(width: 1600, height: 1600)
            )
        }

        let requestSelector =
            NSSelectorFromString("requestImageWithCompletionHandler:")

        guard catalog.responds(to: requestSelector) else {
            mediaControlsArtworkRequestInFlight = false
            setArtworkDebug(
                "MEDIA CONTROLS has an artwork catalog, " +
                "but it cannot request an image"
            )
            return true
        }

        typealias ArtworkCompletion =
            @convention(block) (UIImage?, NSError?) -> Void
        typealias RequestImageFunction =
            @convention(c) (
                AnyObject,
                Selector,
                ArtworkCompletion
            ) -> Void

        let requestImage = unsafeBitCast(
            catalog.method(for: requestSelector),
            to: RequestImageFunction.self
        )

        let completion: ArtworkCompletion = { [weak self] image, error in
            DispatchQueue.main.async {
                guard let self else { return }

                self.mediaControlsArtworkRequestInFlight = false

                if let image {
                    if let imageData =
                        image.jpegData(compressionQuality: 0.98) {
                        self.setArtwork(image, data: imageData)
                    } else {
                        self.setArtwork(image, data: nil)
                    }
                    return
                }

                self.setArtworkDebug(
                    "MEDIA CONTROLS artwork request failed\n" +
                    "title: \(title)\n" +
                    "error: \(error?.localizedDescription ?? "<nil>")"
                )
            }
        }

        requestImage(catalog, requestSelector, completion)
        return true
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

        if let originSymbol = dlsym(
            handle,
            "MRMediaRemoteGetLocalOrigin"
        ) {
            mediaRemoteGetLocalOrigin = unsafeBitCast(
                originSymbol,
                to: MRMediaRemoteGetLocalOrigin.self
            )
        }

        if let directArtworkSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingArtwork"
        ) {
            mediaRemoteGetNowPlayingArtwork = unsafeBitCast(
                directArtworkSymbol,
                to: MRMediaRemoteGetNowPlayingArtwork.self
            )
        }

        if let getClientForOriginSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingClientForOrigin"
        ) {
            mediaRemoteGetClientForOrigin = unsafeBitCast(
                getClientForOriginSymbol,
                to: MRMediaRemoteGetNowPlayingClientForOrigin.self
            )
        }

        if let getClientsSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingClients"
        ) {
            mediaRemoteGetNowPlayingClients = unsafeBitCast(
                getClientsSymbol,
                to: MRMediaRemoteGetNowPlayingClients.self
            )
        }

        if let getPlayerForClientSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingPlayerForClient"
        ) {
            mediaRemoteGetPlayerForClient = unsafeBitCast(
                getPlayerForClientSymbol,
                to: MRMediaRemoteGetNowPlayingPlayerForClient.self
            )
        }

        if let simplePlayerInfoSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingInfoForPlayer"
        ) {
            mediaRemoteGetInfoForPlayerSimple = unsafeBitCast(
                simplePlayerInfoSymbol,
                to: MRMediaRemoteGetNowPlayingInfoForPlayerSimple.self
            )
        }

        if let getClientSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingClient"
        ) {
            mediaRemoteGetNowPlayingClient = unsafeBitCast(
                getClientSymbol,
                to: MRMediaRemoteGetNowPlayingClient.self
            )
        }

        if let infoForClientSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingInfoForClient"
        ) {
            mediaRemoteGetInfoForClient = unsafeBitCast(
                infoForClientSymbol,
                to: MRMediaRemoteGetNowPlayingInfoForClient.self
            )
        }

        if let displayIDSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingApplicationDisplayID"
        ) {
            mediaRemoteGetAppDisplayID = unsafeBitCast(
                displayIDSymbol,
                to: MRMediaRemoteGetNowPlayingApplicationDisplayID.self
            )
        }

        if let infoForAppSymbol = dlsym(
            handle,
            "MRMediaRemoteGetNowPlayingInfoForApp"
        ) {
            mediaRemoteGetInfoForApp = unsafeBitCast(
                infoForAppSymbol,
                to: MRMediaRemoteGetNowPlayingInfoForApp.self
            )
        }

        if let bundleIDSymbol = dlsym(
            handle,
            "MRNowPlayingClientGetBundleIdentifier"
        ) {
            mediaRemoteClientBundleID = unsafeBitCast(
                bundleIDSymbol,
                to: MRNowPlayingClientGetBundleIdentifier.self
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
            "direct artwork: \(mediaRemoteGetNowPlayingArtwork != nil)\n" +
            "now-playing client: \(mediaRemoteGetNowPlayingClient != nil)\n" +
            "client-for-origin: \(mediaRemoteGetClientForOrigin != nil)\n" +
            "all clients: \(mediaRemoteGetNowPlayingClients != nil)\n" +
            "player-for-client: \(mediaRemoteGetPlayerForClient != nil)\n" +
            "player info(simple): \(mediaRemoteGetInfoForPlayerSimple != nil)\n" +
            "client info: \(mediaRemoteGetInfoForClient != nil)\n" +
            "app display ID: \(mediaRemoteGetAppDisplayID != nil)\n" +
            "app info: \(mediaRemoteGetInfoForApp != nil)\n" +
            "local origin: \(mediaRemoteGetLocalOrigin != nil)\n" +
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
        // Match Apple's own accessory Now Playing path first:
        // local origin -> client for origin -> client info with artwork.
        if tryOriginSpecificNowPlayingClient() {
            return
        }

        if tryEnumeratedNowPlayingClients() {
            return
        }

        if tryAppSpecificNowPlaying() {
            return
        }

        if tryClientSpecificNowPlaying() {
            return
        }

        if tryDirectNowPlayingArtwork() {
            return
        }

        if refreshArtworkFromEmbeddedSystemModule() {
            return
        }

        if refreshArtworkFromSystemMediaControls() {
            return
        }

        if tryArtworkFromActivePlayerPath() {
            return
        }

        refreshArtworkFromLegacyAPIs()
    }

    @discardableResult
    private func tryOriginSpecificNowPlayingClient() -> Bool {
        guard
            let getLocalOrigin = mediaRemoteGetLocalOrigin,
            let getClientForOrigin = mediaRemoteGetClientForOrigin,
            let getInfoForClient = mediaRemoteGetInfoForClient
        else {
            return false
        }

        guard let origin = getLocalOrigin() else {
            setArtworkDebug(
                "ORIGIN CLIENT ROUTE\n" +
                "local origin: NIL"
            )
            return true
        }

        getClientForOrigin(
            origin,
            DispatchQueue.main
        ) { [weak self] client, error in
            guard let self else { return }

            let errorString: String
            if let error {
                errorString = String(describing: error)
            } else {
                errorString = "<nil>"
            }

            guard let client else {
                self.setArtworkDebug(
                    "ORIGIN CLIENT ROUTE\n" +
                    "client: NIL\n" +
                    "error: \(errorString)"
                )
                return
            }

            var bundle = "<unknown>"
            if let getBundleID = self.mediaRemoteClientBundleID,
               let unmanaged = getBundleID(client) {
                bundle = unmanaged.takeUnretainedValue() as String
            } else if let value =
                (client as? NSObject)?.value(forKey: "bundleIdentifier")
                    as? String {
                bundle = value
            }

            getInfoForClient(
                client,
                origin,
                true,
                DispatchQueue.main
            ) { [weak self] infoObject in
                guard let self else { return }

                let info = infoObject as? [String: Any] ?? [:]
                let title =
                    info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
                let artist =
                    info["kMRMediaRemoteNowPlayingInfoArtist"] as? String

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

                self.setArtworkDebug(
                    "ORIGIN CLIENT ROUTE\n" +
                    "client: YES\n" +
                    "bundle: \(bundle)\n" +
                    "error: \(errorString)\n" +
                    "keys: \(info.count)\n" +
                    "title: \(title ?? "<nil>")\n" +
                    "artist: \(artist ?? "<nil>")\n" +
                    "artwork bytes: \(artworkData?.count ?? 0)"
                )

                if let artworkData,
                   let image = UIImage(data: artworkData) {
                    self.setArtwork(image, data: artworkData)
                    return
                }

                if title != nil || artist != nil {
                    self.fetchArtworkFallback(
                        title: title,
                        artist: artist,
                        album:
                            info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
                    )
                }
            }
        }

        return true
    }

    @discardableResult
    private func tryEnumeratedNowPlayingClients() -> Bool {
        guard
            let getClients = mediaRemoteGetNowPlayingClients,
            let getPlayerForClient = mediaRemoteGetPlayerForClient,
            let getInfoForPlayer = mediaRemoteGetInfoForPlayerSimple,
            let playerPathClass = NSClassFromString("MRPlayerPath")
        else {
            return false
        }

        getClients(DispatchQueue.main) { [weak self] clients in
            guard let self else { return }

            let allClients = (clients as? [AnyObject]) ?? []

            guard !allClients.isEmpty else {
                self.setArtworkDebug(
                    "ENUM ROUTE\n" +
                    "clients: 0"
                )
                return
            }

            var completed = 0
            var summaries: [String] = []

            for client in allClients {
                var bundle = "<unknown>"
                if let getBundleID = self.mediaRemoteClientBundleID,
                   let unmanaged = getBundleID(client) {
                    bundle = unmanaged.takeUnretainedValue() as String
                } else if let value =
                    (client as? NSObject)?.value(forKey: "bundleIdentifier")
                        as? String {
                    bundle = value
                }

                getPlayerForClient(
                    client,
                    nil,
                    DispatchQueue.main
                ) { [weak self] player in
                    guard let self else { return }

                    guard let player else {
                        completed += 1
                        summaries.append("\(bundle): no player")
                        if completed == allClients.count {
                            self.setArtworkDebug(
                                "ENUM ROUTE\n" +
                                "clients: \(allClients.count)\n" +
                                summaries.prefix(5).joined(separator: "\n")
                            )
                        }
                        return
                    }

                    let classObject: AnyObject = playerPathClass as AnyObject
                    let allocSelector = NSSelectorFromString("alloc")
                    let initSelector =
                        NSSelectorFromString("initWithOrigin:client:player:")

                    guard
                        let allocated = classObject
                            .perform(allocSelector)?
                            .takeUnretainedValue() as AnyObject?
                    else {
                        completed += 1
                        summaries.append("\(bundle): playerPath alloc failed")
                        return
                    }

                    typealias InitPlayerPathFunction =
                        @convention(c) (
                            AnyObject,
                            Selector,
                            AnyObject?,
                            AnyObject,
                            AnyObject
                        ) -> AnyObject?

                    let imp = (allocated as AnyObject).method(for: initSelector)
                    let initPlayerPath = unsafeBitCast(
                        imp,
                        to: InitPlayerPathFunction.self
                    )

                    guard let playerPath = initPlayerPath(
                        allocated,
                        initSelector,
                        nil,
                        client,
                        player
                    ) else {
                        completed += 1
                        summaries.append("\(bundle): playerPath init failed")
                        return
                    }

                    getInfoForPlayer(
                        playerPath,
                        true,
                        DispatchQueue.main
                    ) { [weak self] infoObject in
                        guard let self else { return }

                        completed += 1
                        let info = infoObject as? [String: Any] ?? [:]
                        let title =
                            info["kMRMediaRemoteNowPlayingInfoTitle"]
                                as? String
                        let artist =
                            info["kMRMediaRemoteNowPlayingInfoArtist"]
                                as? String

                        var artworkData =
                            info["kMRMediaRemoteNowPlayingInfoArtworkData"]
                                as? Data

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
                            self.setArtworkDebug(
                                "ENUM ROUTE SUCCESS\n" +
                                "bundle: \(bundle)\n" +
                                "title: \(title ?? "<nil>")\n" +
                                "artist: \(artist ?? "<nil>")\n" +
                                "artwork bytes: \(artworkData.count)"
                            )
                            self.setArtwork(image, data: artworkData)
                            return
                        }

                        if title != nil || artist != nil {
                            self.setArtworkDebug(
                                "ENUM ROUTE METADATA\n" +
                                "bundle: \(bundle)\n" +
                                "title: \(title ?? "<nil>")\n" +
                                "artist: \(artist ?? "<nil>")\n" +
                                "artwork bytes: 0"
                            )
                            self.fetchArtworkFallback(
                                title: title,
                                artist: artist,
                                album:
                                    info[
                                        "kMRMediaRemoteNowPlayingInfoAlbum"
                                    ] as? String
                            )
                            return
                        }

                        summaries.append(
                            "\(bundle): keys=\(info.count), art=\(artworkData?.count ?? 0)"
                        )

                        if completed == allClients.count &&
                           self.artworkView.image == nil {
                            self.setArtworkDebug(
                                "ENUM ROUTE\n" +
                                "clients: \(allClients.count)\n" +
                                summaries.prefix(6).joined(separator: "\n")
                            )
                        }
                    }
                }
            }
        }

        return true
    }

    @discardableResult
    private func tryAppSpecificNowPlaying() -> Bool {
        guard
            let getDisplayID = mediaRemoteGetAppDisplayID,
            let getInfoForApp = mediaRemoteGetInfoForApp
        else {
            return false
        }

        getDisplayID(DispatchQueue.main) { [weak self] displayID in
            guard let self else { return }

            guard let displayID, CFStringGetLength(displayID) > 0 else {
                self.setArtworkDebug(
                    "APP ROUTE\n" +
                    "display ID: NIL\n" +
                    "app-info symbol: YES"
                )
                return
            }

            let displayString = displayID as String
            let origin = self.mediaRemoteGetLocalOrigin?()

            getInfoForApp(
                displayID,
                origin,
                true,
                DispatchQueue.main
            ) { [weak self] infoObject in
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

                if artworkData == nil {
                    for value in info.values {
                        if let data = value as? Data,
                           UIImage(data: data) != nil {
                            artworkData = data
                            break
                        }
                    }
                }

                self.setArtworkDebug(
                    "APP ROUTE\n" +
                    "display ID: \(displayString)\n" +
                    "keys: \(info.count)\n" +
                    "title: \(title)\n" +
                    "artist: \(artist)\n" +
                    "artwork bytes: \(artworkData?.count ?? 0)"
                )

                if let artworkData,
                   let image = UIImage(data: artworkData) {
                    self.setArtwork(image, data: artworkData)
                    return
                }

                if title != "<nil>" || artist != "<nil>" {
                    self.fetchArtworkFallback(
                        title: title == "<nil>" ? nil : title,
                        artist: artist == "<nil>" ? nil : artist,
                        album:
                            info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
                    )
                }
            }
        }

        return true
    }

    @discardableResult
    private func tryClientSpecificNowPlaying() -> Bool {
        guard
            let getClient = mediaRemoteGetNowPlayingClient,
            let getInfoForClient = mediaRemoteGetInfoForClient
        else {
            return false
        }

        getClient(DispatchQueue.main) { [weak self] client in
            guard let self else { return }

            self.mediaRemoteGetAppDisplayID?(DispatchQueue.main) { displayID in
                guard self.artworkView.image == nil else { return }

                let displayString =
                    (displayID as String?) ?? "<nil>"

                guard let client else {
                    self.setArtworkDebug(
                        "CLIENT ROUTE\n" +
                        "active client: NIL\n" +
                        "display ID: \(displayString)\n" +
                        "NOTE: direct-artwork fallback paused for diagnosis"
                    )
                    return
                }

                var bundleString = "<unavailable>"
                if let getBundleID = self.mediaRemoteClientBundleID,
                   let unmanaged = getBundleID(client) {
                    bundleString = unmanaged.takeUnretainedValue() as String
                }

                let origin = self.mediaRemoteGetLocalOrigin?()

                getInfoForClient(
                    client,
                    origin,
                    true,
                    DispatchQueue.main
                ) { [weak self] infoObject in
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

                    if artworkData == nil {
                        for value in info.values {
                            if let data = value as? Data,
                               UIImage(data: data) != nil {
                                artworkData = data
                                break
                            }
                        }
                    }

                    self.setArtworkDebug(
                        "CLIENT ROUTE\n" +
                        "client: YES\n" +
                        "bundle: \(bundleString)\n" +
                        "display ID: \(displayString)\n" +
                        "keys: \(info.count)\n" +
                        "title: \(title)\n" +
                        "artist: \(artist)\n" +
                        "artwork bytes: \(artworkData?.count ?? 0)"
                    )

                    if let artworkData,
                       let image = UIImage(data: artworkData) {
                        self.setArtwork(image, data: artworkData)
                        return
                    }

                    if !title.isEmpty && title != "<nil>" ||
                       !artist.isEmpty && artist != "<nil>" {
                        self.fetchArtworkFallback(
                            title: title == "<nil>" ? nil : title,
                            artist: artist == "<nil>" ? nil : artist,
                            album:
                                info["kMRMediaRemoteNowPlayingInfoAlbum"]
                                    as? String
                        )
                        return
                    }

                    self.setArtworkDebug(
                        "CLIENT ROUTE\n" +
                        "client: YES\n" +
                        "bundle: \(bundleString)\n" +
                        "display ID: \(displayString)\n" +
                        "keys: \(info.count)\n" +
                        "title: \(title)\n" +
                        "artist: \(artist)\n" +
                        "artwork bytes: \(artworkData?.count ?? 0)\n" +
                        "NOTE: direct-artwork fallback paused for diagnosis"
                    )
                }
            }
        }

        return true
    }

    @discardableResult
    private func tryDirectNowPlayingArtwork() -> Bool {
        guard
            let getLocalOrigin = mediaRemoteGetLocalOrigin,
            let getArtwork = mediaRemoteGetNowPlayingArtwork
        else {
            return false
        }

        guard let origin = getLocalOrigin() else {
            setArtworkDebug("DIRECT ARTWORK: local origin is nil")
            return false
        }

        setArtworkDebug(
            "DIRECT ARTWORK\n" +
            "Requesting the system Now Playing artwork channel..."
        )

        getArtwork(
            origin,
            DispatchQueue.main
        ) { [weak self] artworkObject in
            guard let self else { return }

            guard let artworkObject else {
                self.setArtworkDebug(
                    "DIRECT ARTWORK callback fired\n" +
                    "artwork object: NIL"
                )
                return
            }

            guard let copyArtworkData = self.mediaRemoteCopyArtworkData else {
                self.setArtworkDebug(
                    "DIRECT ARTWORK callback fired\n" +
                    "artwork object: YES\n" +
                    "image-data copier: unavailable"
                )
                return
            }

            guard let copied = copyArtworkData(artworkObject) else {
                self.setArtworkDebug(
                    "DIRECT ARTWORK callback fired\n" +
                    "artwork object: YES\n" +
                    "image data: NIL"
                )
                return
            }

            let data = copied.takeRetainedValue() as Data

            guard let image = UIImage(data: data) else {
                self.setArtworkDebug(
                    "DIRECT ARTWORK callback fired\n" +
                    "artwork bytes: \(data.count)\n" +
                    "UIImage decode: FAILED"
                )
                return
            }

            self.setArtworkDebug(
                "DIRECT ARTWORK SUCCESS\n" +
                "artwork bytes: \(data.count)"
            )
            self.setArtwork(image, data: data)
        }

        return true
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

        if let mediaControlsHandle {
            dlclose(mediaControlsHandle)
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
