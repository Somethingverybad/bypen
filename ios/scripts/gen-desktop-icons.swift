// swift scripts/gen-desktop-icons.swift <корень bypen>
// Пакует существующую фирменную графику в системные ресурсы Windows и macOS.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
let source = NSImage(contentsOf: root.appendingPathComponent("ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"))!
let stump = NSImage(contentsOf: root.appendingPathComponent("design/stump.svg"))!
func png(_ size: Int, mac: Bool = false, menu: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(size)
    if menu {
        // Прозрачный фон и полный цвет — никакого template-режима или щита.
        let w = s * 674.073 / 774
        stump.draw(in: NSRect(x: (s-w)/2, y: 0, width: w, height: s))
    } else if mac {
        let r = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
        NSBezierPath(roundedRect: r, xRadius: s * 0.19, yRadius: s * 0.19).addClip()
        source.draw(in: r)
    } else { source.draw(in: NSRect(x: 0, y: 0, width: s, height: s)) }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
func write(_ data: Data, _ path: String) throws {
    let url = root.appendingPathComponent(path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}
func le<T: FixedWidthInteger>(_ n: T) -> Data {
    var v = n.littleEndian
    return withUnsafeBytes(of: &v) { Data($0) }
}
let sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
// Малые иконки — обычные 32-bit DIB: их понимают также ExtractIconEx и старые
// обработчики миниатюр Проводника. PNG оставляем только для 256 px.
func iconData(_ size: Int) -> Data {
    if size == 256 { return png(size) }
    let rep = NSBitmapImageRep(data: png(size))!
    let maskSize = ((size + 31) / 32) * 4 * size
    var d = le(UInt32(40)) + le(Int32(size)) + le(Int32(size * 2))
    d.append(le(UInt16(1))); d.append(le(UInt16(32)))
    d.append(le(UInt32(0))); d.append(le(UInt32(size * size * 4)))
    for _ in 0..<4 { d.append(le(UInt32(0))) }
    for y in (0..<size).reversed() {
        for x in 0..<size {
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            d.append(contentsOf: [UInt8((c.blueComponent * 255).rounded()), UInt8((c.greenComponent * 255).rounded()), UInt8((c.redComponent * 255).rounded()), UInt8((c.alphaComponent * 255).rounded())])
        }
    }
    d.append(Data(count: maskSize))
    return d
}
let images = sizes.map { iconData($0) }
var ico = le(UInt16(0)) + le(UInt16(1)) + le(UInt16(sizes.count))
var offset = 6 + sizes.count * 16
for (size, data) in zip(sizes, images) {
    ico.append(contentsOf: [UInt8(size % 256), UInt8(size % 256), 0, 0])
    ico.append(le(UInt16(1))); ico.append(le(UInt16(32)))
    ico.append(le(UInt32(data.count))); ico.append(le(UInt32(offset)))
    offset += data.count
}
for data in images { ico.append(data) }
try write(ico, "desktop/assets/icon.ico")

// Отдельный AppIcon для macOS: iOS-каталог не меняется.
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let file = "icon-\(size)@\(scale)x.png"
        try write(png(size * scale, mac: true), "ios/Mac/Assets.xcassets/AppIcon.appiconset/\(file)")
        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": file])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try write(JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]), "ios/Mac/Assets.xcassets/AppIcon.appiconset/Contents.json")
try write(JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted]), "ios/Mac/Assets.xcassets/Contents.json")
try write(png(22, menu: true), "ios/Mac/Resources/MenuBarIcon.png")
try write(png(44, menu: true), "ios/Mac/Resources/MenuBarIcon@2x.png")
print("Windows ICO (9 размеров), macOS AppIcon и цветная иконка строки меню готовы")
