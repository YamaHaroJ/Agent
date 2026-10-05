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

func racingCPath(in rect: NSRect) -> NSBezierPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y
        )
    }

    let path = NSBezierPath()
    path.move(to: p(0.82, 0.73))
    path.line(to: p(0.73, 0.57))
    path.line(to: p(0.48, 0.57))
    path.curve(
        to: p(0.39, 0.51),
        controlPoint1: p(0.45, 0.57),
        controlPoint2: p(0.41, 0.55)
    )
    path.line(to: p(0.30, 0.43))
    path.curve(
        to: p(0.33, 0.36),
        controlPoint1: p(0.27, 0.40),
        controlPoint2: p(0.28, 0.36)
    )
    path.line(to: p(0.69, 0.36))
    path.line(to: p(0.61, 0.24))
    path.line(to: p(0.31, 0.24))
    path.curve(
        to: p(0.17, 0.42),
        controlPoint1: p(0.22, 0.24),
        controlPoint2: p(0.15, 0.32)
    )
    path.line(to: p(0.31, 0.62))
    path.curve(
        to: p(0.57, 0.73),
        controlPoint1: p(0.37, 0.70),
        controlPoint2: p(0.47, 0.73)
    )
    path.close()
    return path
}

func addSubtleBorder(_ canvas: NSRect) {
    let borderRect = canvas.insetBy(dx: 42, dy: 42)
    let border = NSBezierPath(
        roundedRect: borderRect,
        xRadius: 205,
        yRadius: 205
    )
    border.lineWidth = 4
    NSColor(calibratedWhite: 0.42, alpha: 0.62).setStroke()
    border.stroke()
}

func italicWordmarkFont(size: CGFloat) -> NSFont {
    if let font = NSFont(name: "AvenirNextCondensed-HeavyItalic", size: size) {
        return font
    }
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
}

func drawCenteredWordmark(_ text: String, canvas: NSRect) {
    var fontSize: CGFloat = 320
    var font = italicWordmarkFont(size: fontSize)
    var attr: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    var string = NSAttributedString(string: text, attributes: attr)

    while string.size().width > canvas.width * 0.82 && fontSize > 180 {
        fontSize -= 8
        font = italicWordmarkFont(size: fontSize)
        attr[.font] = font
        string = NSAttributedString(string: text, attributes: attr)
    }

    let size = string.size()
    string.draw(
        at: NSPoint(
            x: canvas.midX - size.width / 2,
            y: canvas.midY - size.height / 2 - font.descender * 0.55
        )
    )
}

func makeMaster(kind: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()

    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)

    if kind == "ClockChromeC" {
        let bg = NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.025, green: 0.045, blue: 0.065, alpha: 1),
            NSColor(calibratedWhite: 0.005, alpha: 1)
        ])!
        bg.draw(in: canvas, angle: -55)

        let logo = racingCPath(in: canvas)
        let metal = NSGradient(colors: [
            NSColor(calibratedWhite: 1.00, alpha: 1),
            NSColor(calibratedWhite: 0.84, alpha: 1),
            NSColor(calibratedWhite: 0.42, alpha: 1),
            NSColor(calibratedWhite: 0.88, alpha: 1)
        ])!
        metal.draw(in: logo, angle: -90)

        let highlight = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.36),
            NSColor.white.withAlphaComponent(0.00)
        ])!
        highlight.draw(
            in: NSRect(x: 0, y: 650, width: 1024, height: 374),
            angle: -90
        )

        let flare = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.80),
            NSColor(calibratedRed: 0.40, green: 0.70, blue: 1.00, alpha: 0.24),
            NSColor.clear
        ])!
        flare.draw(
            in: NSBezierPath(
                ovalIn: NSRect(x: 810, y: 300, width: 150, height: 150)
            ),
            relativeCenterPosition: NSPoint(x: 0, y: 0)
        )

        addSubtleBorder(canvas)
    } else {
        NSColor.black.setFill()
        NSBezierPath(rect: canvas).fill()

        if kind == "ClockWordmark" {
            let sweep = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.00),
                NSColor.white.withAlphaComponent(0.09),
                NSColor.white.withAlphaComponent(0.00)
            ])!
            sweep.draw(
                in: NSRect(x: 155, y: 300, width: 720, height: 430),
                angle: -58
            )

            drawCenteredWordmark("Clock", canvas: canvas)

            let line = NSBezierPath()
            line.move(to: NSPoint(x: 230, y: 365))
            line.curve(
                to: NSPoint(x: 825, y: 365),
                controlPoint1: NSPoint(x: 420, y: 330),
                controlPoint2: NSPoint(x: 650, y: 390)
            )
            line.lineWidth = 9
            NSColor.white.withAlphaComponent(0.55).setStroke()
            line.stroke()
        } else {
            let logo = racingCPath(in: canvas)
            NSColor.white.setFill()
            logo.fill()
        }

        addSubtleBorder(canvas)
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
            throw NSError(domain: "ClockIconGenerator", code: 1)
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

func writePreviewSet(named name: String, under assetsURL: URL) throws {
    let fm = FileManager.default
    let previewName = "\(name)Preview"
    let setURL = assetsURL.appendingPathComponent("\(previewName).imageset")

    try? fm.removeItem(at: setURL)
    try fm.createDirectory(
        at: setURL,
        withIntermediateDirectories: true
    )

    let master = makeMaster(kind: name)
    let files = [
        ("preview.png", 256, "1x"),
        ("preview@2x.png", 512, "2x"),
        ("preview@3x.png", 768, "3x")
    ]

    var images: [[String: String]] = []

    for (filename, pixels, scale) in files {
        guard let data = pngData(master, pixels: pixels) else {
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
    try writePreviewSet(named: name, under: assetsURL)
    print("Generated \(name)")
}
