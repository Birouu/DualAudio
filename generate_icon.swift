import AppKit

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        guard let copy = self.copy() as? NSImage else { return self }
        copy.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: copy.size)
        rect.fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }
}

let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let outputDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (name, size) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.25, green: 0.47, blue: 0.95, alpha: 1.0),
        NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.85, alpha: 1.0)
    ])
    gradient?.draw(in: bgPath, angle: -45)

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let tinted = symbol.tinted(with: .white)
        let symbolSize = tinted.size
        let symbolRect = NSRect(
            x: (size - symbolSize.width) / 2,
            y: (size - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height)
        tinted.draw(in: symbolRect)
    }

    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else { continue }

    let path = "\(outputDir)/\(name).png"
    try? pngData.write(to: URL(fileURLWithPath: path))
}

print("Icon PNGs generated at \(outputDir)")
