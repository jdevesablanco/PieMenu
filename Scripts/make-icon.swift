#!/usr/bin/env swift
// Genera AppIcon.icns: menú circular con una porción resaltada, en el morado del pack.
// Uso: swift Scripts/make-icon.swift Resources/AppIcon.icns [preview.png]
import AppKit
import CoreGraphics

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // fondo: squircle con degradado morado
    let bg = CGPath(roundedRect: CGRect(x: 40, y: 40, width: 944, height: 944), cornerWidth: 215, cornerHeight: 215, transform: nil)
    ctx.saveGState(); ctx.addPath(bg); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.62, green: 0.38, blue: 0.98, alpha: 1), CGColor(red: 0.33, green: 0.20, blue: 0.80, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 100, y: 1000), end: CGPoint(x: 900, y: 40), options: [])
    ctx.restoreGState()

    // anillo de cristal oscuro con el hueco central
    let c = CGPoint(x: 512, y: 512), outer: CGFloat = 340, inner: CGFloat = 128
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
    ring.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.3))
    ctx.setFillColor(CGColor(red: 0.13, green: 0.08, blue: 0.30, alpha: 0.78))
    ctx.addPath(ring); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18)); ctx.setLineWidth(5)
    ctx.addPath(ring); ctx.strokePath()

    // porción resaltada (arriba a la derecha), con esquinas redondeadas
    let n = 6, step = CGFloat.pi * 2 / CGFloat(n)
    let mid = CGFloat.pi / 2 - step       // la segunda porción, en sentido horario desde arriba
    let corner: CGFloat = 34, pad: CGFloat = 14
    let ro = outer - pad - corner, ri = inner + pad + corner
    let ho = step / 2 - asin((pad + corner) / ro), hi = step / 2 - asin((pad + corner) / ri)
    let wedge = CGMutablePath()
    wedge.addArc(center: c, radius: ro, startAngle: mid + ho, endAngle: mid - ho, clockwise: true)
    wedge.addArc(center: c, radius: ri, startAngle: mid - hi, endAngle: mid + hi, clockwise: false)
    wedge.closeSubpath()
    ctx.saveGState()
    ctx.setAlpha(0.3)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineJoin(.round); ctx.setLineWidth(corner * 2)
    ctx.addPath(wedge); ctx.fillPath()
    ctx.addPath(wedge); ctx.strokePath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // «iconos» de las porciones: cuadrados redondeados blancos, el resaltado más grande
    let mr = (outer + inner) / 2
    for i in 0..<n {
        let a = CGFloat.pi / 2 - CGFloat(i) * step
        let p = CGPoint(x: c.x + cos(a) * mr, y: c.y + sin(a) * mr)
        let side: CGFloat = i == 1 ? 132 : 104
        ctx.setFillColor(CGColor(gray: 1, alpha: i == 1 ? 1 : 0.85))
        ctx.addPath(CGPath(roundedRect: CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side),
                           cornerWidth: side * 0.24, cornerHeight: side * 0.24, transform: nil))
        ctx.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let set = (out as NSString).deletingLastPathComponent + "/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                               ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (n, px) in sizes { try! render(px).write(to: URL(fileURLWithPath: "\(set)/icon_\(n).png")) }
if CommandLine.arguments.count > 2 { try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", set, "-o", out]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(atPath: set)
print("OK", out)
