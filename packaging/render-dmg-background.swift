import AppKit
import CoreText

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: swift render-dmg-background.swift font-directory output.png\n", stderr)
    exit(2)
}
let fonts = URL(fileURLWithPath: arguments[1], isDirectory: true)
for file in ["InstrumentSerif-Italic.ttf", "BricolageGrotesque-Regular.ttf"] {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(file) as CFURL, .process, nil)
}

let width = 672
let height = 390
let canvas = NSImage(size: NSSize(width: width, height: height), flipped: false) { bounds in
    let verticalOffset = bounds.height - 360
    func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
    NSGradient(starting: color(0.26, 0.09, 0.22), ending: color(0.085, 0.065, 0.14))?
        .draw(in: bounds, angle: -37)
    NSGradient(starting: color(0.69, 0.24, 0.47, 0.22), ending: color(0.69, 0.24, 0.47, 0))?
        .draw(fromCenter: CGPoint(x: 220, y: 205), radius: 10, toCenter: CGPoint(x: 220, y: 205),
              radius: 300, options: [.drawsBeforeStartingLocation])

    func text(_ value: String, font: NSFont, ink: NSColor, y: CGFloat) {
        let label = NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: ink])
        label.draw(at: CGPoint(x: (bounds.width - label.size().width) / 2, y: y + verticalOffset))
    }

    let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 18, dy: 18), xRadius: 25, yRadius: 25)
    color(1, 0.79, 0.89, 0.18).setStroke()
    edge.lineWidth = 1
    edge.stroke()

    for x in [185.0, 487.0] {
        let well = NSBezierPath(roundedRect: CGRect(x: x - 67, y: 92 + verticalOffset, width: 134, height: 143), xRadius: 27, yRadius: 27)
        NSGradient(starting: color(0.89, 0.69, 0.82, 0.22), ending: color(0.99, 0.88, 0.94, 0.84))?
            .draw(in: well, angle: -90)
        color(1, 0.84, 0.93, 0.45).setStroke()
        well.stroke()
    }

    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 306, y: 168 + verticalOffset))
    arrow.line(to: CGPoint(x: 366, y: 168 + verticalOffset))
    arrow.move(to: CGPoint(x: 352, y: 181 + verticalOffset))
    arrow.line(to: CGPoint(x: 366, y: 168 + verticalOffset))
    arrow.line(to: CGPoint(x: 352, y: 155 + verticalOffset))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0.99, 0.66, 0.81, 0.86).setStroke()
    arrow.stroke()

    text("Yoru", font: NSFont(name: "InstrumentSerif-Italic", size: 62) ?? .systemFont(ofSize: 54),
         ink: color(1, 0.93, 0.97), y: 259)
    text("Glissez Yoru dans Applications", font: NSFont(name: "BricolageGrotesque-Regular", size: 17) ?? .systemFont(ofSize: 17),
         ink: color(1, 0.85, 0.92), y: 46)
    return true
}

guard let bytes = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: bytes),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
