// 生成 App 图标 iconset（渐变圆角底 + 白色咖啡杯）
// 用法: swift gen-icon.swift /path/to/AppIcon.iconset
import Cocoa

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write("usage: gen-icon.swift <out.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = args[1]

func renderIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    // 圆角底 + 渐变
    let inset = size * 0.045
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let path = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.23, yRadius: size * 0.23)
    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.62, alpha: 1),
        NSColor(calibratedRed: 0.09, green: 0.66, blue: 0.66, alpha: 1),
    ])!
    grad.draw(in: path, angle: -60)

    // 咖啡杯
    if let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .medium)
        if let cup = symbol.withSymbolConfiguration(cfg) {
            let target = NSRect(x: (size - cup.size.width) / 2,
                                y: (size - cup.size.height) / 2,
                                width: cup.size.width, height: cup.size.height)
            let white = NSImage(size: cup.size)
            white.lockFocus()
            cup.draw(in: NSRect(origin: .zero, size: cup.size))
            NSColor.white.set()
            NSRect(origin: .zero, size: cup.size).fill(using: .sourceAtop)
            white.unlockFocus()
            white.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
    return img
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (px, name) in sizes {
    let image = renderIcon(size: CGFloat(px))
    writePNG(image, pixels: px, to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("iconset written to \(outDir)")
