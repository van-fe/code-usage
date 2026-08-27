import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift generate_app_icon.swift <output.png>\n", stderr)
    exit(2)
}

let canvasSize = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create icon bitmap")
}

bitmap.size = NSSize(width: canvasSize, height: canvasSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

let tileRect = NSRect(x: 56, y: 56, width: 912, height: 912)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
tile.fill()

NSGraphicsContext.saveGraphicsState()
tile.addClip()
let background = NSGradient(
    starting: NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.25, alpha: 1),
    ending: NSColor(calibratedRed: 0.075, green: 0.08, blue: 0.095, alpha: 1)
)!
background.draw(in: tileRect, angle: -55)
NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.13).setStroke()
tile.lineWidth = 8
tile.stroke()

let foreground = NSColor.white.withAlphaComponent(0.94)
let center = NSPoint(x: 512, y: 512)
let gaugeRadius: CGFloat = 292
let gaugeRect = NSRect(
    x: center.x - gaugeRadius,
    y: center.y - gaugeRadius,
    width: gaugeRadius * 2,
    height: gaugeRadius * 2
)

foreground.setStroke()
let outerRing = NSBezierPath(ovalIn: gaugeRect)
outerRing.lineWidth = 46
outerRing.stroke()

foreground.setFill()
for degrees in stride(from: 135.0, through: 405.0, by: 45.0) {
    let radians = degrees * .pi / 180
    let dotRadius: CGFloat = 20
    let dotDistance: CGFloat = 188
    let dotCenter = NSPoint(
        x: center.x + cos(radians) * dotDistance,
        y: center.y + sin(radians) * dotDistance
    )
    NSBezierPath(ovalIn: NSRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )).fill()
}

let needleAngle = 45.0 * Double.pi / 180
let needleLength: CGFloat = 222
let needle = NSBezierPath()
needle.move(to: center)
needle.line(to: NSPoint(
    x: center.x + cos(needleAngle) * needleLength,
    y: center.y + sin(needleAngle) * needleLength
))
needle.lineWidth = 52
needle.lineCapStyle = .round
needle.stroke()

let hubRadius: CGFloat = 42
NSBezierPath(ovalIn: NSRect(
    x: center.x - hubRadius,
    y: center.y - hubRadius,
    width: hubRadius * 2,
    height: hubRadius * 2
)).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
