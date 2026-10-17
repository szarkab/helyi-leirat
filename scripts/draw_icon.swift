import AppKit
let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.48, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
NSColor.white.setStroke()
for (index, height) in [100.0, 210, 330, 440, 330, 210, 100].enumerated() {
    let x = 230.0 + Double(index) * 94
    let line = NSBezierPath()
    line.lineWidth = 38
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: x, y: 512 - height / 2))
    line.line(to: NSPoint(x: x, y: 512 + height / 2))
    line.stroke()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
// icns container, 1024px PNG-backed icon entry.
var data = Data("icns".utf8)
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
data.append(bigEndian(png.count + 16))
data.append(Data("ic10".utf8))
data.append(bigEndian(png.count + 8))
data.append(png)
try data.write(to: URL(fileURLWithPath: destination))
