import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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
        return (1.06, -0.045, 0.0)
    case "ClockWordmark":
        // Pixel-measured from the 2048px iPad screenshot.
        return (1.06, -0.108, 0.0)
    case "ClockChromeC":
        // Pixel-measured from the 2048px iPad screenshot.
        return (1.06, -0.103, 0.0)
    default:
        return (1.0, 0.0, 0.0)
    }
}

func loadCGImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func renderPNG(
    source: CGImage,
    name: String,
    pixels: Int
) throws -> Data {
    let width = pixels
    let height = pixels
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let byteCount = bytesPerRow * height

    let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: byteCount,
        alignment: 64
    )
    defer { buffer.deallocate() }

    memset(buffer, 0, byteCount)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo =
        CGImageAlphaInfo.noneSkipLast.rawValue |
        CGBitmapInfo.byteOrder32Big.rawValue

    guard let context = CGContext(
        data: buffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw NSError(
            domain: "ClockIconGenerator",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"]
        )
    }

    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.interpolationQuality = .high

    // Draw the source in its native orientation. The previous CTM flip was
    // rotating the alternate app icons relative to the correctly oriented
    // in-app previews.
    let p = placement(for: name)
    let side = CGFloat(pixels) * p.scale
    let x = (CGFloat(pixels) - side) / 2 + CGFloat(pixels) * p.x
    let y = (CGFloat(pixels) - side) / 2 - CGFloat(pixels) * p.y

    context.draw(
        source,
        in: CGRect(
            x: x,
            y: y,
            width: side,
            height: side
        )
    )

    // Do not install another silent all-black build.
    let bytes = buffer.bindMemory(
        to: UInt8.self,
        capacity: byteCount
    )
    var brightPixels = 0
    let step = max(1, pixels / 64)

    for yy in stride(from: 0, to: height, by: step) {
        for xx in stride(from: 0, to: width, by: step) {
            let i = yy * bytesPerRow + xx * bytesPerPixel
            let r = Int(bytes[i])
            let g = Int(bytes[i + 1])
            let b = Int(bytes[i + 2])
            if max(r, max(g, b)) > 38 {
                brightPixels += 1
            }
        }
    }

    if brightPixels < 20 {
        throw NSError(
            domain: "ClockIconGenerator",
            code: 11,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Generated \(name) is effectively black; refusing to continue."
            ]
        )
    }

    guard let outputImage = context.makeImage() else {
        throw NSError(
            domain: "ClockIconGenerator",
            code: 12,
            userInfo: [NSLocalizedDescriptionKey: "Could not create output image"]
        )
    }

    let mutable = NSMutableData()

    guard let destination = CGImageDestinationCreateWithData(
        mutable,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(
            domain: "ClockIconGenerator",
            code: 13,
            userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"]
        )
    }

    CGImageDestinationAddImage(destination, outputImage, nil)

    guard CGImageDestinationFinalize(destination) else {
        throw NSError(
            domain: "ClockIconGenerator",
            code: 14,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"]
        )
    }

    return mutable as Data
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: url, options: .atomic)
}

func writeIconSet(name: String, source: CGImage, assetsURL: URL) throws {
    let fm = FileManager.default
    let setURL = assetsURL.appendingPathComponent("\(name).appiconset")

    try? fm.removeItem(at: setURL)
    try fm.createDirectory(at: setURL, withIntermediateDirectories: true)

    var images: [[String: String]] = []

    for slot in slots {
        let data = try renderPNG(
            source: source,
            name: name,
            pixels: slot.pixels
        )

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

func writePreviewSet(name: String, source: CGImage, assetsURL: URL) throws {
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
        let data = try renderPNG(
            source: source,
            name: name,
            pixels: pixels
        )

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

    guard let source = loadCGImage(masterURL) else {
        fputs(
            "Could not load master artwork: \(masterURL.path)\n",
            stderr
        )
        exit(3)
    }

    try writeIconSet(
        name: name,
        source: source,
        assetsURL: assetsURL
    )
    try writePreviewSet(
        name: name,
        source: source,
        assetsURL: assetsURL
    )

    print("Generated and validated \(name)")
}
