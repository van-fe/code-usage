import Foundation

guard CommandLine.arguments.count >= 4,
      (CommandLine.arguments.count - 2).isMultiple(of: 2) else {
    fputs("Usage: swift package_icns.swift <output.icns> <type> <image.png> [...]\n", stderr)
    exit(2)
}

func bigEndianData(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

var elements = Data()
var index = 2
while index < CommandLine.arguments.count {
    let type = CommandLine.arguments[index]
    let imagePath = CommandLine.arguments[index + 1]
    guard type.utf8.count == 4 else {
        fatalError("ICNS element type must contain four ASCII bytes: \(type)")
    }

    let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
    elements.append(type.data(using: .ascii)!)
    elements.append(bigEndianData(UInt32(imageData.count + 8)))
    elements.append(imageData)
    index += 2
}

var container = Data("icns".utf8)
container.append(bigEndianData(UInt32(elements.count + 8)))
container.append(elements)
try container.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
