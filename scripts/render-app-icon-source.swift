import AppKit
// Renders the 1024px app icon source: the black/white-eyes ㅎ·ㄴ characters centered on an off-white macOS tile.
let svg = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = URL(fileURLWithPath: CommandLine.arguments[2])
// Find the characters' bounding box (SVG units) from an alpha scan.
let scan = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1254, pixelsHigh: 1254, bitsPerSample: 8, samplesPerPixel: 4,
                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scan)
svg.draw(in: NSRect(x: 0, y: 0, width: 1254, height: 1254)); NSGraphicsContext.restoreGraphicsState()
var minX = 1254, maxX = 0, minY = 1254, maxY = 0
for y in 0..<1254 { for x in 0..<1254 where scan.colorAt(x: x, y: y)!.alphaComponent > 0.02 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
let box = NSRect(x: minX, y: 1254 - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1) // flip to bottom-left origin
print("bbox", box)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 1024, height: 1024)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.shadowBlurRadius = 24
shadow.shadowColor = NSColor(white: 0, alpha: 0.28); shadow.set()
NSColor(srgbRed: 0.965, green: 0.953, blue: 0.925, alpha: 1).setFill(); path.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(srgbRed: 0.985, green: 0.978, blue: 0.958, alpha: 1),
           ending: NSColor(srgbRed: 0.935, green: 0.922, blue: 0.892, alpha: 1))!.draw(in: path, angle: -90)
let scale = 600 / box.width
let size = NSSize(width: box.width * scale, height: box.height * scale)
let dest = NSRect(x: 512 - size.width / 2, y: 512 - size.height / 2 - 6, width: size.width, height: size.height)
svg.draw(in: dest, from: NSRect(x: box.minX, y: box.minY, width: box.width, height: box.height), operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: out)
