import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift generate_app_icon.swift <input.svg> <output.png>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let canvasSize = 1024
guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("Unable to load AppIcon SVG: \(sourceURL.path)")
}

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
NSGraphicsContext.current?.imageInterpolation = .high
sourceImage.draw(
    in: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize),
    from: NSRect(origin: .zero, size: sourceImage.size),
    operation: .sourceOver,
    fraction: 1
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon PNG")
}
try png.write(to: outputURL)
