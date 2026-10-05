// Clock Art Bridge: system-wide Now Playing reader for macOS 15.4+.
//
// This dylib is intentionally loaded into Apple's /usr/bin/perl process.
// mediaremoted permits that platform process to read system Now Playing data,
// while ordinary third-party processes receive empty metadata.
//
// The bridge is read-only. It emits one JSON line whenever Now Playing changes.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetClient)(dispatch_queue_t, void (^)(id));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(BOOL));
typedef NSString *(*MRClientBundleID)(id);
typedef void (*MRRegisterNotifications)(dispatch_queue_t);

static void *gMediaRemote = NULL;

static id MRConstant(const char *name) {
    void *address = dlsym(gMediaRemote, name);
    return address ? *(__unsafe_unretained id *)address : nil;
}

static void EmitSample(void) {
    MRGetInfo getInfo =
        (MRGetInfo)dlsym(gMediaRemote, "MRMediaRemoteGetNowPlayingInfo");
    MRGetClient getClient =
        (MRGetClient)dlsym(gMediaRemote, "MRMediaRemoteGetNowPlayingClient");
    MRGetIsPlaying getIsPlaying =
        (MRGetIsPlaying)dlsym(
            gMediaRemote,
            "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
        );
    MRClientBundleID getBundleID =
        (MRClientBundleID)dlsym(
            gMediaRemote,
            "MRNowPlayingClientGetBundleIdentifier"
        );

    if (!getInfo) {
        fprintf(stderr, "ClockArtBridge: MRMediaRemoteGetNowPlayingInfo missing\n");
        fflush(stderr);
        return;
    }

    dispatch_queue_t queue =
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    __block NSDictionary *info = nil;
    __block NSString *bundleID = nil;
    __block BOOL playing = NO;

    dispatch_group_t group = dispatch_group_create();

    dispatch_group_enter(group);
    getInfo(queue, ^(NSDictionary *result) {
        info = result;
        dispatch_group_leave(group);
    });

    if (getClient && getBundleID) {
        dispatch_group_enter(group);
        getClient(queue, ^(id client) {
            if (client) {
                bundleID = getBundleID(client);
            }
            dispatch_group_leave(group);
        });
    }

    if (getIsPlaying) {
        dispatch_group_enter(group);
        getIsPlaying(queue, ^(BOOL result) {
            playing = result;
            dispatch_group_leave(group);
        });
    }

    long waitResult = dispatch_group_wait(
        group,
        dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)
    );

    if (waitResult != 0) {
        fprintf(stderr, "ClockArtBridge: sample timed out\n");
        fflush(stderr);
        return;
    }

    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"playing"] = @(playing);

    if (bundleID.length) {
        out[@"bundleIdentifier"] = bundleID;
    }

    if ([info isKindOfClass:[NSDictionary class]]) {
        NSString *title =
            info[@"kMRMediaRemoteNowPlayingInfoTitle"];
        NSString *artist =
            info[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSString *album =
            info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
        NSData *artwork =
            info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        NSString *mime =
            info[@"kMRMediaRemoteNowPlayingInfoArtworkMIMEType"];

        if (title.length) out[@"title"] = title;
        if (artist.length) out[@"artist"] = artist;
        if (album.length) out[@"album"] = album;
        if (mime.length) out[@"artworkMimeType"] = mime;

        if ([artwork isKindOfClass:[NSData class]] && artwork.length > 0) {
            out[@"artworkData"] =
                [artwork base64EncodedStringWithOptions:0];
        }
    }

    out[@"sampleEpoch"] = @([[NSDate date] timeIntervalSince1970]);

    NSData *json =
        [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];

    if (!json) {
        return;
    }

    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void StartStream(void) {
    MRRegisterNotifications registerNotifications =
        (MRRegisterNotifications)dlsym(
            gMediaRemote,
            "MRMediaRemoteRegisterForNowPlayingNotifications"
        );

    if (!registerNotifications) {
        fprintf(
            stderr,
            "ClockArtBridge: notification registration unavailable\n"
        );
        fflush(stderr);
        return;
    }

    dispatch_queue_t queue =
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    registerNotifications(queue);

    NSOperationQueue *delivery = [[NSOperationQueue alloc] init];
    delivery.maxConcurrentOperationCount = 1;

    NSArray<NSString *> *symbolNames = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        @"kMRNowPlayingPlaybackQueueChangedNotification"
    ];

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    for (NSString *symbolName in symbolNames) {
        NSString *notificationName =
            MRConstant(symbolName.UTF8String);

        if (!notificationName.length) {
            continue;
        }

        [center addObserverForName:notificationName
                           object:nil
                            queue:delivery
                       usingBlock:^(__unused NSNotification *note) {
            EmitSample();
        }];
    }

    // Send the current state immediately.
    EmitSample();
}

__attribute__((constructor))
static void ClockArtBridgeBoot(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);

    gMediaRemote = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_NOW
    );

    if (!gMediaRemote) {
        fprintf(
            stderr,
            "ClockArtBridge: could not load MediaRemote: %s\n",
            dlerror()
        );
        fflush(stderr);
        return;
    }

    // Starting MediaRemote work directly inside the dylib constructor can
    // race dyld/XPC initialization. Wait until the host process is running.
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 700 * NSEC_PER_MSEC),
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
        ^{
            StartStream();
        }
    );
}
