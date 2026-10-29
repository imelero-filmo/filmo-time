import AppKit
// usage: render <svg> <out.png> <px> [inset-fraction]
let a = CommandLine.arguments
let img = NSImage(contentsOf: URL(fileURLWithPath: a[1]))!
let px = Double(a[3])!
let inset = a.count > 4 ? Double(a[4])! : 0
let scale = min(px / img.size.width, px / img.size.height)
let w = (img.size.width * scale).rounded(), h = (img.size.height * scale).rounded()
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: w * inset, y: h * inset, width: w * (1 - 2 * inset), height: h * (1 - 2 * inset)))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
