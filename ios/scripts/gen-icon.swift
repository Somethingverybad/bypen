// swift scripts/svg2png.swift ../design/stump.svg stump.png && swift scripts/gen-icon.swift stump.png <папка> — иконка «пень» из Figma: фон — градиент фрейма (сэмплы sRGB: верх-лево #345C54 → низ-право #578159),
// пень — SVG группы 19:179 (design/stump.svg), отрисованный в PNG с прозрачностью, стоит в (175, 125) размером 674×774 на холсте 1024.
import AppKit
let stumpPath = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
let stump = NSImage(contentsOfFile: stumpPath)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ h: UInt32) -> CGColor { CGColor(colorSpace: cs, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, 1])! }
func background(_ ctx: CGContext, _ s: CGFloat) {
    let g = CGGradient(colorsSpace: cs, colors: [rgb(0x345C54), rgb(0x345C54), rgb(0x466F56), rgb(0x578159)] as CFArray, locations: [0, 0.38, 0.62, 1])!
    // CoreGraphics: y снизу. Направление (0.4, 0.6) сверху-слева вниз-вправо.
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: s), end: CGPoint(x: s * 0.4 / 0.6 * 0.6, y: s - s * 1.0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func make(_ size: Int, alpha: Bool, draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx, CGFloat(size)); return ctx.makeImage()!
}
func save(_ img: CGImage, _ name: String) {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir + "/" + name))
}
// пень в координатах макета 1024 (y макета сверху вниз → в CG снизу)
func drawStump(_ ctx: CGContext, _ s: CGFloat, scale: CGFloat = 1, center: Bool = false) {
    let k = s / 1024
    var w = 674.073 * k * scale, h = 774 * k * scale
    var x = 175 * k, y = s - (125 * k) - h
    if center { x = (s - w) / 2; y = (s - h) / 2 } else { w = 674.073 * k; h = 774 * k; y = s - 125 * k - h }
    ctx.draw(stump, in: CGRect(x: x, y: y, width: w, height: h))
}
// iOS / macOS: полный квадрат без альфы
save(make(1024, alpha: false) { c, s in background(c, s); drawStump(c, s) }, "ios-icon.png")
// Android: устаревший значок (квадрат) и адаптивный: фон + пень (≈58 % высоты холста 108 dp)
let legacy: [(String, Int)] = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]
let adaptive: [(String, Int)] = [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]
for (d, s) in legacy { save(make(s, alpha: false) { c, sz in background(c, sz); drawStump(c, sz) }, "ic_launcher-\(d).png") }
for (d, s) in adaptive {
    save(make(s, alpha: true) { c, sz in drawStump(c, sz, scale: 0.58 / (774.0 / 1024.0), center: true) }, "ic_fg-\(d).png")
    save(make(s, alpha: false) { c, sz in background(c, sz) }, "ic_bg-\(d).png")
}
print("ok")
