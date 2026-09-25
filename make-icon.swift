import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect.insetBy(dx: 70, dy: 70), xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.98, alpha: 1.0),
    NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.55, alpha: 1.0)
])!
gradient.draw(in: path, angle: -90)

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 480, weight: .bold),
    .foregroundColor: NSColor.white
]
let str = NSAttributedString(string: "$", attributes: attrs)
let s = str.size()
str.draw(at: NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2))
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("generate png failed\n".data(using: .utf8)!)
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-base.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
