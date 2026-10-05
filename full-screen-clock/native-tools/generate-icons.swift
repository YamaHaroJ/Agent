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

func italicFont(size: CGFloat, weight: NSFont.Weight = .black) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
}

func drawTextCentered(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    foreground: NSColor,
    shadow: NSShadow? = nil
) {
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: foreground
    ]
    if let shadow {
        attributes[.shadow] = shadow
    }

    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    let point = NSPoint(
        x: rect.midX - size.width / 2,
        y: rect.midY - size.height / 2 - font.descender
    )
    string.draw(at: point)
}

func makeMaster(kind: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()

    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)

    switch kind {
    case "ClockChromeC":
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0.12, alpha: 1),
            NSColor(calibratedWhite: 0.02, alpha: 1)
        ])!
        gradient.draw(in: canvas, angle: -55)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -16)

        drawTextCentered(
            "C",
            in: canvas.offsetBy(dx: 14, dy: 2),
            font: italicFont(size: 690),
            foreground: NSColor(calibratedWhite: 0.82, alpha: 1),
            shadow: shadow
        )

        let gloss = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.32),
            NSColor.white.withAlphaComponent(0.00)
        ])!
        gloss.draw(
            in: NSBezierPath(
                roundedRect: NSRect(x: 0, y: 540, width: 1024, height: 484),
                xRadius: 0,
                yRadius: 0
            ),
            angle: -90
        )

    case "ClockWordmark":
        NSColor.black.setFill()
        NSBezierPath(rect: canvas).fill()
        drawTextCentered(
            "Clock",
            in: canvas.offsetBy(dx: 0, dy: 0),
            font: italicFont(size: 300, weight: .bold),
            foreground: .white
        )

    default:
        NSColor.black.setFill()
        NSBezierPath(rect: canvas).fill()
        drawTextCentered(
            "C",
            in: canvas.offsetBy(dx: 12, dy: 2),
            font: italicFont(size: 690),
            foreground: .white
        )
    }

    image.unlockFocus()
    return image
}

func pngData(_ image: NSImage, pixels: Int) -> Data? {
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

    rep.size = NSSize(width: CGFloat(pixels), height: CGFloat(pixels))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(x: 0, y: 0, width: 1024, height: 1024),
        operation: .copy,
        fraction: 1
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func writeIconSet(named name: String, under assetsURL: URL) throws {
    let fm = FileManager.default
    let setURL = assetsURL.appendingPathComponent("\(name).appiconset")

    try? fm.removeItem(at: setURL)
    try fm.createDirectory(
        at: setURL,
        withIntermediateDirectories: true
    )

    let master = makeMaster(kind: name)

    for slot in slots {
        guard let data = pngData(master, pixels: slot.pixels) else {
            throw NSError(
                domain: "ClockIconGenerator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PNG generation failed"]
            )
        }

        try data.write(
            to: setURL.appendingPathComponent(slot.filename),
            options: .atomic
        )
    }

    let images: [[String: String]] = slots.map { slot in
        [
            "idiom": slot.idiom,
            "size": slot.size,
            "scale": slot.scale,
            "filename": slot.filename
        ]
    }

    let contents: [String: Any] = [
        "images": images,
        "info": [
            "author": "xcode",
            "version": 1
        ]
    ]

    let json = try JSONSerialization.data(
        withJSONObject: contents,
        options: [.prettyPrinted, .sortedKeys]
    )

    try json.write(
        to: setURL.appendingPathComponent("Contents.json"),
        options: .atomic
    )
}

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icons.swift /path/to/Assets.xcassets\n", stderr)
    exit(2)
}

let assetsURL = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(
    at: assetsURL,
    withIntermediateDirectories: true
)

for name in ["ClockItalicC", "ClockWordmark", "ClockChromeC"] {
    try writeIconSet(named: name, under: assetsURL)
    print("Generated \(name)")
}
