// Отрисовать SVG (например design/stump.svg) в PNG с прозрачностью: swift scripts/svg2png.swift in.svg out.png
import AppKit
let img = NSImage(contentsOfFile: CommandLine.arguments[1])
print("loaded:", img != nil, img?.size as Any, img?.representations.map { String(describing: type(of: $0)) } as Any)
if let img {
    let s = CGSize(width: 1348, height: 1548)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s.width), pixelsHigh: Int(s.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: CGRect(origin: .zero, size: s))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("written")
}
