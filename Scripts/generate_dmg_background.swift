import AppKit
import Foundation

guard (2...4).contains(CommandLine.arguments.count) else {
    fputs("Usage: generate_dmg_background.swift OUTPUT.png [BASE.png] [SCALE]\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let baseURL = CommandLine.arguments.count == 3
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : CommandLine.arguments.count == 4
        ? URL(fileURLWithPath: CommandLine.arguments[2])
        : nil
let scale = CommandLine.arguments.count == 4
    ? CGFloat(Double(CommandLine.arguments[3]) ?? 1)
    : 1
guard scale == 1 || scale == 2 else {
    fputs("SCALE must be 1 or 2\n", stderr)
    exit(2)
}
let canvasSize = NSSize(width: 780, height: 500)
let pixelSize = NSSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(pixelSize.width),
    pixelsHigh: Int(pixelSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create DMG background canvas\n", stderr)
    exit(1)
}
// Keep PNG metadata at 72 DPI. Finder uses the @2x filename suffix to map
// the 1560 × 1000 bitmap onto the 780 × 500 logical background exactly once.
bitmap.size = pixelSize

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: scale, y: scale)

let canvasRect = NSRect(origin: .zero, size: canvasSize)
if let baseURL, let base = NSImage(contentsOf: baseURL) {
    base.draw(
        in: canvasRect,
        from: NSRect(origin: .zero, size: base.size),
        operation: .copy,
        fraction: 1
    )
} else {
    NSColor.white.setFill()
    NSBezierPath(rect: canvasRect).fill()

    let panelRect = NSRect(x: 50, y: 64, width: 680, height: 260)
    NSColor(calibratedWhite: 0.955, alpha: 1).setFill()
    NSBezierPath(roundedRect: panelRect, xRadius: 16, yRadius: 16).fill()
}

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center

let title = "将 CodeUsage 拖到“应用程序”完成安装"
title.draw(
    in: NSRect(x: 40, y: 394, width: 700, height: 36),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
        .paragraphStyle: titleStyle
    ]
)

let subtitle = "按住左侧应用图标，拖到右侧文件夹后松开"
subtitle.draw(
    in: NSRect(x: 40, y: 360, width: 700, height: 28),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
        .paragraphStyle: titleStyle
    ]
)

// The real application and Applications folder icons are placed by Finder.
// Draw only the directional cue between their fixed icon positions.
let arrowColor = NSColor(calibratedRed: 0.10, green: 0.46, blue: 0.96, alpha: 1)
arrowColor.setStroke()

let arrow = NSBezierPath()
arrow.lineWidth = 9
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 346, y: 167))
arrow.line(to: NSPoint(x: 430, y: 167))
arrow.move(to: NSPoint(x: 405, y: 192))
arrow.line(to: NSPoint(x: 430, y: 167))
arrow.line(to: NSPoint(x: 405, y: 142))
arrow.stroke()

let footnote = "首次启动若被 macOS 拦截，请右键 CodeUsage.app 并选择“打开”"
footnote.draw(
    in: NSRect(x: 40, y: 42, width: 700, height: 22),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
        .paragraphStyle: titleStyle
    ]
)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render DMG background\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL, options: .atomic)
} catch {
    fputs("Could not write DMG background: \(error.localizedDescription)\n", stderr)
    exit(1)
}
