// Generates the vPhone Workstation app icon (1024²).
// Bold bright-blue phone outline + green corner status badge over a bright
// white backdrop of vphone commands. Drawn in CoreGraphics/CoreText — no SVG tooling.
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit
import CoreGraphics
import CoreText

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024
let csp = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: csp, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func c(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: csp, components: [CGFloat(r)/255, CGFloat(g)/255, CGFloat(b)/255, a])!
}
// SVG (top-down) rect → CoreGraphics (bottom-up) rounded-rect path.
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: S - y - h, width: w, height: h), cornerWidth: rad, cornerHeight: rad, transform: nil)
}
func fill(_ p: CGPath, _ col: CGColor) { ctx.addPath(p); ctx.setFillColor(col); ctx.fillPath() }
func strokeP(_ p: CGPath, _ col: CGColor, _ lw: CGFloat) { ctx.addPath(p); ctx.setStrokeColor(col); ctx.setLineWidth(lw); ctx.strokePath() }

// Ground squircle + vertical gradient (clip stays on for the transcript).
let sq = rr(0, 0, 1024, 1024, 230)
ctx.saveGState(); ctx.addPath(sq); ctx.clip()
let grad = CGGradient(colorsSpace: csp, colors: [c(15, 20, 32), c(6, 9, 14)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 1024), end: .zero, options: [])

// Command backdrop — bright white mono, clipped to the squircle.
let font = NSFont.monospacedSystemFont(ofSize: 100, weight: .regular)
let lines: [(String, CGFloat, CGFloat)] = [
    ("$ vphone-cli", 52, 290), ("vm create 27b4", 52, 418), ("[+] fw patch jb", 52, 546),
    ("=== restore ===", 52, 674), ("[+] first boot", 52, 802), ("$ vm launch", 52, 930),
]
ctx.textMatrix = .identity
let textAttrs: [NSAttributedString.Key: Any] = [
    .font: font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): c(255, 255, 255, 0.85),
]
for (s, x, ybase) in lines {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: textAttrs))
    ctx.textPosition = CGPoint(x: x, y: S - ybase)
    CTLineDraw(line, ctx)
}
ctx.restoreGState()

// Opaque phone outline over the text.
fill(rr(356, 182, 312, 660, 84), c(11, 15, 24))
strokeP(rr(356, 182, 312, 660, 84), c(91, 155, 255), 30)
fill(rr(466, 252, 92, 26, 13), c(106, 166, 255))

// Green corner status badge (SVG cx=810 cy=210 r=88).
fill(CGPath(ellipseIn: CGRect(x: 810 - 88, y: (S - 210) - 88, width: 176, height: 176), transform: nil), c(63, 211, 90))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
