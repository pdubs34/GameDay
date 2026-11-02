// Renders the 1024px app icon: swift scripts/make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let navyTop = NSColor(srgbRed: 0.09, green: 0.16, blue: 0.32, alpha: 1)
let navyBottom = NSColor(srgbRed: 0.03, green: 0.06, blue: 0.14, alpha: 1)
let orange = NSColor(srgbRed: 1, green: 0.353, blue: 0.122, alpha: 1)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background
NSGradient(starting: navyTop, ending: navyBottom)!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

// Calendar page with a drop shadow
let page = NSRect(x: 212, y: 190, width: 600, height: 620)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -18)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
NSBezierPath(roundedRect: page, xRadius: 96, yRadius: 96).fill()
NSGraphicsContext.restoreGraphicsState()

// Orange header band, clipped to the page's rounded top
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: page, xRadius: 96, yRadius: 96).addClip()
orange.setFill()
NSRect(x: page.minX, y: page.maxY - 170, width: page.width, height: 170).fill()
NSGraphicsContext.restoreGraphicsState()

// Binder rings
navyBottom.setFill()
for x in [page.minX + 150, page.maxX - 150] {
    NSBezierPath(roundedRect: NSRect(x: x - 26, y: page.maxY - 70, width: 52, height: 130), xRadius: 26, yRadius: 26).fill()
}

// Sport symbol on the page
let config = NSImage.SymbolConfiguration(pointSize: 290, weight: .heavy)
    .applying(.init(paletteColors: [navyTop]))
if let symbol = NSImage(systemSymbolName: "sportscourt.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let body = NSRect(x: page.minX, y: page.minY, width: page.width, height: page.height - 170)
    let s = symbol.size
    symbol.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height))
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
