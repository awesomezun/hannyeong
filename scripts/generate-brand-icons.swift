import AppKit

let sources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let iconset = output.appendingPathComponent("Hannyeong-v3.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

enum IconError: Error {
    case unreadableImage(String)
}

func load(_ name: String) throws -> NSImage {
    let url = sources.appendingPathComponent(name)
    guard let image = NSImage(contentsOf: url) else { throw IconError.unreadableImage(url.path) }
    return image
}

func bitmap(_ image: NSImage, width: Int, height: Int, scale: Int = 1) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current!.imageInterpolation = .high
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    NSColor.clear.setFill()
    bounds.fill(using: .copy)
    let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
    let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
    let fitted = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                        width: size.width, height: size.height)
    image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, _ url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let app = try load("AppIcon-v3-source.png")
// Menu bar / input-switch icon: the ㅎ and ㄴ characters' faces, pre-rendered pixel-exact at 1x and 2x
// (black ink + alpha; eyes and the gap between the two characters are transparent so the template tints cleanly).
func loadRep(_ name: String) throws -> NSBitmapImageRep {
    let url = sources.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else {
        throw IconError.unreadableImage(url.path)
    }
    rep.size = NSSize(width: 22, height: 16)
    return rep
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let rep = bitmap(app, width: points, height: points, scale: scale)
        try savePNG(rep, iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
let appPNG = bitmap(app, width: 1024, height: 1024)
assert(appPNG.colorAt(x: 0, y: 0)!.alphaComponent == 0, "App icon must retain transparent corners")
try savePNG(appPNG, output.appendingPathComponent("Hannyeong.png"))

let menuReps = [try loadRep("InputSource-character-22x16.png"), try loadRep("InputSource-character-22x16@2x.png")]
assert(menuReps[0].pixelsWide == 22 && menuReps[0].pixelsHigh == 16, "1x menu icon must be 22x16 pixels")
assert(menuReps[1].pixelsWide == 44 && menuReps[1].pixelsHigh == 32, "2x menu icon must be 44x32 pixels")
let menuImage = NSImage(size: NSSize(width: 22, height: 16))
menuImage.isTemplate = true
for rep in menuReps { menuImage.addRepresentation(rep) }
assert(menuReps[0].colorAt(x: 0, y: 0)!.alphaComponent == 0,
       "Menu icon must retain transparent corners")
let colors = (0..<32).flatMap { y in (0..<44).map { menuReps[1].colorAt(x: $0, y: y)! } }
assert(colors.contains { $0.alphaComponent > 0.9 && $0.redComponent < 0.1 }, "Template icon must have black ink")
assert(colors.allSatisfy { $0.alphaComponent < 0.05 || $0.redComponent < 0.1 }, "Template icon must be pure black ink")
let coverage = colors.filter { $0.alphaComponent > 0.5 }.count
assert(coverage > 500 && coverage < 1300, "Character faces must fill the frame while keeping eyes and gaps open")
try menuImage.tiffRepresentation!.write(to: output.appendingPathComponent("HannyeongInput-v8Template.tiff"))
try savePNG(menuReps[0], output.appendingPathComponent("menu-22x16.png"))
try savePNG(menuReps[1], output.appendingPathComponent("menu-22x16@2x.png"))

// A diagnostic contact sheet shows the badge at its native size and larger inspection sizes.
let preview = NSImage(size: NSSize(width: 560, height: 320))
preview.lockFocus()
NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 560, height: 320).fill()
app.draw(in: NSRect(x: 12, y: 12, width: 296, height: 296))
menuImage.draw(in: NSRect(x: 348, y: 170, width: 132, height: 96))
menuImage.draw(in: NSRect(x: 350, y: 90, width: 22, height: 16))
menuImage.draw(in: NSRect(x: 404, y: 86, width: 33, height: 24))
menuImage.draw(in: NSRect(x: 468, y: 82, width: 44, height: 32))
preview.unlockFocus()
try savePNG(NSBitmapImageRep(data: preview.tiffRepresentation!)!, output.appendingPathComponent("preview.png"))
print("한녕 icons: 10 app sizes, 22x16-point character template icon at 1x/2x")
