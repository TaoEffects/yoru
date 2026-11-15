import AppKit
import CoreGraphics

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
func star(_ ctx: CGContext, x: CGFloat, y: CGFloat, r: CGFloat) {
    ctx.move(to: CGPoint(x: x, y: y + r))
    ctx.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + r * 0.18, y: y + r * 0.18))
    ctx.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x + r * 0.18, y: y - r * 0.18))
    ctx.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - r * 0.18, y: y - r * 0.18))
    ctx.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x - r * 0.18, y: y + r * 0.18))
    ctx.fillPath()
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
for base in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let size = base * multiplier
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let rect = CGRect(x: 91, y: 91, width: 842, height: 842)
        let contour = CGPath(roundedRect: rect, cornerWidth: 192, cornerHeight: 192, transform: nil)
        ctx.addPath(contour)
        ctx.clip()
        let gradient = CGGradient(colorsSpace: space, colors: [color(0.75, 0.98, 0.89), color(0.28, 0.76, 0.67)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 230, y: 930), end: CGPoint(x: 820, y: 93), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.setFillColor(color(0.047, 0.080, 0.10))
        ctx.move(to: CGPoint(x: 523, y: 748))
        ctx.addCurve(to: CGPoint(x: 662, y: 410), control1: CGPoint(x: 392, y: 567), control2: CGPoint(x: 491, y: 420))
        ctx.addCurve(to: CGPoint(x: 733, y: 426), control1: CGPoint(x: 691, y: 409), control2: CGPoint(x: 711, y: 417))
        ctx.addCurve(to: CGPoint(x: 513, y: 281), control1: CGPoint(x: 698, y: 338), control2: CGPoint(x: 611, y: 281))
        ctx.addCurve(to: CGPoint(x: 281, y: 514), control1: CGPoint(x: 385, y: 281), control2: CGPoint(x: 281, y: 385))
        ctx.addCurve(to: CGPoint(x: 523, y: 748), control1: CGPoint(x: 281, y: 643), control2: CGPoint(x: 382, y: 753))
        ctx.fillPath()
        star(ctx, x: 669, y: 633, r: 80)
        star(ctx, x: 777, y: 534, r: 43)
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        let name = "icon_\(base)x\(base)" + (multiplier == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
