import AppKit
import Foundation

struct Slot {
    let idiom: String
    let size: String
    let scale: String
    let pixels: Int
    let filename: String
}

let slots: [Slot] = [
    .init(idiom: "iphone", size: "20x20", scale: "2x", pixels: 40, filename: "icon-20@2x.png"),
    .init(idiom: "iphone", size: "20x20", scale: "3x", pixels: 60, filename: "icon-20@3x.png"),
    .init(idiom: "iphone", size: "29x29", scale: "2x", pixels: 58, filename: "icon-29@2x.png"),
    .init(idiom: "iphone", size: "29x29", scale: "3x", pixels: 87, filename: "icon-29@3x.png"),
    .init(idiom: "iphone", size: "40x40", scale: "2x", pixels: 80, filename: "icon-40@2x.png"),
    .init(idiom: "iphone", size: "40x40", scale: "3x", pixels: 120, filename: "icon-40@3x.png"),
    .init(idiom: "iphone", size: "60x60", scale: "2x", pixels: 120, filename: "icon-60@2x.png"),
    .init(idiom: "iphone", size: "60x60", scale: "3x", pixels: 180, filename: "icon-60@3x.png"),
    .init(idiom: "ipad", size: "20x20", scale: "1x", pixels: 20, filename: "icon-20.png"),
    .init(idiom: "ipad", size: "20x20", scale: "2x", pixels: 40, filename: "icon-20@2x-ipad.png"),
    .init(idiom: "ipad", size: "29x29", scale: "1x", pixels: 29, filename: "icon-29.png"),
    .init(idiom: "ipad", size: "29x29", scale: "2x", pixels: 58, filename: "icon-29@2x-ipad.png"),
    .init(idiom: "ipad", size: "40x40", scale: "1x", pixels: 40, filename: "icon-40.png"),
    .init(idiom: "ipad", size: "40x40", scale: "2x", pixels: 80, filename: "icon-40@2x-ipad.png"),
    .init(idiom: "ipad", size: "76x76", scale: "1x", pixels: 76, filename: "icon-76.png"),
    .init(idiom: "ipad", size: "76x76", scale: "2x", pixels: 152, filename: "icon-76@2x.png"),
    .init(idiom: "ipad", size: "83.5x83.5", scale: "2x", pixels: 167, filename: "icon-83.5@2x.png"),
    .init(idiom: "ios-marketing", size: "1024x1024", scale: "1x", pixels: 1024, filename: "icon-1024.png")
]

func placement(for name: String) -> (scale: CGFloat, x: CGFloat, y: CGFloat) {
    switch name {
    case "ClockItalicC":
        return (0.94, -0.020, 0.0)
    case "ClockWordmark":
        return (0.90, -0.050, 0.0)
    case "ClockChromeC":
        return (0.88, -0.080, 0.0)
    default:
        return (1.0, 0.0, 0.0)
    }
}

func pngData(from source: NSImage, name: String, pixels: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 24
    )!

    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixels, height: pixels)).fill()

    let p = placement(for: name)
    let side = CGFloat(pixels) * p.scale
    let x = (CGFloat(pixels) - side) / 2 + CGFloat(pixels) * p.x
    let y = (CGFloat(pixels) - side) / 2 + CGFloat(pixels) * p.y

    source.draw(
        in: NSRect(x: x, y: y, width: side, height: side),
        from: NSRect(origin: .zero, size: source.size),
        operation: .sourceOver,
        fraction: 1
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: url, options: .atomic)
}

func writeIconSet(name: String, source: NSImage, assetsURL: URL) throws {
    let fm = FileManager.default
    let setURL = assetsURL.appendingPathComponent("\(name).appiconset")

    try? fm.removeItem(at: setURL)
    try fm.createDirectory(at: setURL, withIntermediateDirectories: true)

    var images: [[String: String]] = []

    for slot in slots {
        guard let data = pngData(from: source, name: name, pixels: slot.pixels) else {
            throw NSError(domain: "ClockIconGenerator", code: 1)
        }

        try data.write(
            to: setURL.appendingPathComponent(slot.filename),
            options: .atomic
        )

        images.append([
            "idiom": slot.idiom,
            "size": slot.size,
            "scale": slot.scale,
            "filename": slot.filename
        ])
    }

    try writeJSON(
        [
            "images": images,
            "info": ["author": "xcode", "version": 1]
        ],
        to: setURL.appendingPathComponent("Contents.json")
    )
}

func writePreviewSet(name: String, source: NSImage, assetsURL: URL) throws {
    let fm = FileManager.default
    let setURL = assetsURL.appendingPathComponent("\(name)Preview.imageset")

    try? fm.removeItem(at: setURL)
    try fm.createDirectory(at: setURL, withIntermediateDirectories: true)

    let previewSlots: [(String, Int, String)] = [
        ("preview.png", 256, "1x"),
        ("preview@2x.png", 512, "2x"),
        ("preview@3x.png", 768, "3x")
    ]

    var images: [[String: String]] = []

    for (filename, pixels, scale) in previewSlots {
        guard let data = pngData(from: source, name: name, pixels: pixels) else {
            throw NSError(domain: "ClockIconGenerator", code: 2)
        }

        try data.write(
            to: setURL.appendingPathComponent(filename),
            options: .atomic
        )

        images.append([
            "idiom": "universal",
            "scale": scale,
            "filename": filename
        ])
    }

    try writeJSON(
        [
            "images": images,
            "info": ["author": "xcode", "version": 1]
        ],
        to: setURL.appendingPathComponent("Contents.json")
    )
}

guard CommandLine.arguments.count >= 3 else {
    fputs(
        "Usage: generate-icons.swift /path/to/Assets.xcassets /path/to/master-icons\n",
        stderr
    )
    exit(2)
}

let assetsURL = URL(fileURLWithPath: CommandLine.arguments[1])
let mastersURL = URL(fileURLWithPath: CommandLine.arguments[2])

try FileManager.default.createDirectory(
    at: assetsURL,
    withIntermediateDirectories: true
)

let names = ["ClockItalicC", "ClockWordmark", "ClockChromeC"]

for name in names {
    let masterURL = mastersURL.appendingPathComponent("\(name)_master.jpg")

    guard let source = NSImage(contentsOf: masterURL) else {
        fputs("Could not load exact master artwork: \(masterURL.path)\n", stderr)
        exit(3)
    }

    try writeIconSet(name: name, source: source, assetsURL: assetsURL)
    try writePreviewSet(name: name, source: source, assetsURL: assetsURL)
    print("Generated exact \(name)")
}
