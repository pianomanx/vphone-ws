// Frames a raw window screenshot for docs: rounded corners + soft drop shadow
// on transparent padding, so it reads cleanly on light or dark READMEs.
// Usage: swift scripts/frame_shot.swift <in.png> <out.png>
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: frame_shot <in.png> <out.png>\n", stderr); exit(1) }

guard let src = NSImage(contentsOf: URL(fileURLWithPath: args[1])),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("cannot load \(args[1])\n", stderr); exit(1)
}

let w = CGFloat(cg.width), h = CGFloat(cg.height)
let pad: CGFloat = 64, radius: CGFloat = 16
let W = Int(w + pad * 2), H = Int(h + pad * 2)
let csp = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: csp, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
    CGColor(colorSpace: csp, components: [r, g, b, a])!
}

let rect = CGRect(x: pad, y: pad, width: w, height: h)
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Shadow pass — fill the rounded rect so it casts a soft shadow onto the transparent ground.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 48, color: color(0, 0, 0, 0.42))
ctx.addPath(path); ctx.setFillColor(color(0.06, 0.07, 0.09, 1)); ctx.fillPath()
ctx.restoreGState()

// Image pass — clip to the rounded rect and draw the shot (upright as-is in a bottom-up context).
ctx.saveGState()
ctx.addPath(path); ctx.clip()
ctx.draw(cg, in: rect)
ctx.restoreGState()

// Hairline inner border for crispness.
ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                   cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.setStrokeColor(color(1, 1, 1, 0.07)); ctx.setLineWidth(1); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
