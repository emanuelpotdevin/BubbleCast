import AppKit
let out = CommandLine.arguments[1]
for (name, px) in [("16",16),("16@2x",32),("32",32),("32@2x",64),("128",128),("128@2x",256),("256",256),("256@2x",512),("512",512),("512@2x",1024)] {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset), xRadius: s*0.18, yRadius: s*0.18)
    NSGradient(starting: NSColor(red: 0.16, green: 0.18, blue: 0.32, alpha: 1), ending: NSColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 1))!.draw(in: bg, angle: -90)
    NSColor.systemRed.setFill()
    NSBezierPath(ovalIn: NSRect(x: s*0.28, y: s*0.42, width: s*0.22, height: s*0.22)).fill()
    let b = NSRect(x: s*0.50, y: s*0.20, width: s*0.32, height: s*0.32)
    NSColor.white.setFill(); NSBezierPath(ovalIn: b).fill()
    NSColor.systemTeal.setFill(); NSBezierPath(ovalIn: b.insetBy(dx: s*0.025, dy: s*0.025)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
