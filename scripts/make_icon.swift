#!/usr/bin/env swift
//
// Renders the Pockterm app icon: a retro CRT terminal dropped *into* a denim
// pocket. Original CoreGraphics artwork, no third-party marks.
//
// Writes all three iOS 18 variants (light, dark, tinted).
//
// Usage: swift scripts/make_icon.swift [output-dir]
//        (defaults to pockterm/Assets.xcassets/AppIcon.appiconset)
//
// The depth cues that make the computer read as inside rather than on top of
// the pocket, in the order they matter:
//   1. a dark pocket interior visible behind the computer, above the front hem
//   2. a shadow cast down onto the computer by the pocket mouth
//   3. denim stretched into a bulge where the computer pushes the fabric out
//   4. a slight tilt, as an object dropped in a pocket would settle

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024

// MARK: - Palette

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

enum C {
    static let bgTop = rgb(26, 36, 56)
    static let bgBottom = rgb(9, 14, 26)

    static let denimLight = rgb(122, 160, 214)
    static let denimMid = rgb(82, 122, 180)
    static let denimDark = rgb(48, 78, 128)
    static let denimShadow = rgb(28, 48, 84)
    static let pocketInterior = rgb(14, 24, 44)

    static let stitch = rgb(240, 200, 108)
    static let stud = rgb(226, 182, 92)

    static let caseLight = rgb(238, 232, 214)
    static let caseMid = rgb(214, 206, 184)
    static let caseDark = rgb(150, 142, 122)
    static let bezel = rgb(58, 52, 44)

    static let screenDark = rgb(8, 26, 14)
    static let screenLit = rgb(16, 48, 26)
    static let phosphor = rgb(78, 240, 128)
    static let phosphorDim = rgb(52, 200, 100)

}

// MARK: - Small drawing helpers

extension CGContext {
    func fillLinearGradient(_ path: CGPath, _ colors: [CGColor], _ locations: [CGFloat],
                            from p0: CGPoint, to p1: CGPoint) {
        saveGState()
        addPath(path)
        clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: colors as CFArray, locations: locations)!
        drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    func fillRadialGradient(_ path: CGPath, _ colors: [CGColor], _ locations: [CGFloat],
                            center: CGPoint, radius: CGFloat) {
        saveGState()
        addPath(path)
        clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: colors as CFArray, locations: locations)!
        drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
        restoreGState()
    }

    func fill(_ path: CGPath, _ color: CGColor) {
        saveGState(); setFillColor(color); addPath(path); fillPath(); restoreGState()
    }

    func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat, dash: [CGFloat]? = nil,
                cap: CGLineCap = .round) {
        saveGState()
        setStrokeColor(color); setLineWidth(width); setLineCap(cap); setLineJoin(.round)
        if let dash { setLineDash(phase: 0, lengths: dash) }
        addPath(path); strokePath()
        restoreGState()
    }
}

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Geometry
//
// Everything is laid out in a top-left-origin space and flipped once at the end,
// so the numbers below read the same way the picture does.

/// Where the front hem of the pocket crosses the computer. The computer's
/// bottom disappears behind this line.
let hemY: CGFloat = 612
/// Top of the pocket's back panel — the dark interior peeks out between here
/// and the front hem.
let backHemY: CGFloat = 556
let pocketBottomY: CGFloat = 902
let pocketLeftX: CGFloat = 96
let pocketRightX: CGFloat = 928

/// The computer is tilted a few degrees, like it settled into the pocket.
let tilt: CGFloat = -5.5 * .pi / 180
let computerCenter = CGPoint(x: 512, y: 392)
let computerSize = CGSize(width: 442, height: 502)

/// Horizontal span over which the denim is pushed outward by the computer.
/// Kept just inside the computer's tilted footprint so the fabric grips it
/// rather than arcing loosely past it.
let bulgeLeftX: CGFloat = 276
let bulgeRightX: CGFloat = 748
/// How far up the front hem is lifted at the centre of the bulge.
let bulgeLift: CGFloat = 48

/// The hem curve of a pocket panel, left seam to right seam: it sags between
/// the seams and is lifted where the computer stretches the fabric taut.
///
/// `rise` raises the middle of the curve without moving the seam endpoints,
/// which is what turns the gap between the front and back hems into a crescent
/// — zero at the corners, widest at the centre. That crescent is the pocket
/// mouth, and it is the main reason the computer reads as being *inside*.
func hemCurve(rise: CGFloat) -> CGMutablePath {
    let p = CGMutablePath()
    let lift = bulgeLift + rise
    // Fabric pinches down into a trough right beside the computer, which is
    // what makes the denim look gripped around it rather than passing behind.
    let sag = hemY + 30 - rise * 0.55
    p.move(to: CGPoint(x: pocketLeftX, y: hemY - 6))
    // left seam sagging down into the trough
    p.addCurve(to: CGPoint(x: bulgeLeftX, y: sag),
               control1: CGPoint(x: pocketLeftX + 74, y: hemY + 30 - rise * 0.2),
               control2: CGPoint(x: bulgeLeftX - 46, y: sag + 6))
    // over the computer: fabric pulled up tight and fast
    p.addCurve(to: CGPoint(x: 512, y: hemY - lift),
               control1: CGPoint(x: bulgeLeftX + 30, y: sag - 12),
               control2: CGPoint(x: 512 - 132, y: hemY - lift - 4))
    p.addCurve(to: CGPoint(x: bulgeRightX, y: sag),
               control1: CGPoint(x: 512 + 132, y: hemY - lift - 4),
               control2: CGPoint(x: bulgeRightX - 30, y: sag - 12))
    // right trough back up to the seam
    p.addCurve(to: CGPoint(x: pocketRightX, y: hemY - 6),
               control1: CGPoint(x: bulgeRightX + 46, y: sag + 6),
               control2: CGPoint(x: pocketRightX - 74, y: hemY + 30 - rise * 0.2))
    return p
}

/// A full pocket panel: the hem curve closed down around the rounded bottom.
func pocketPanel(rise: CGFloat) -> CGPath {
    let p = hemCurve(rise: rise)
    let bottomY = pocketBottomY
    p.addCurve(to: CGPoint(x: pocketRightX - 34, y: bottomY - 70),
               control1: CGPoint(x: pocketRightX + 6, y: hemY + 150),
               control2: CGPoint(x: pocketRightX - 6, y: bottomY - 150))
    p.addCurve(to: CGPoint(x: 512, y: bottomY),
               control1: CGPoint(x: pocketRightX - 62, y: bottomY - 16),
               control2: CGPoint(x: 512 + 140, y: bottomY))
    p.addCurve(to: CGPoint(x: pocketLeftX + 34, y: bottomY - 70),
               control1: CGPoint(x: 512 - 140, y: bottomY),
               control2: CGPoint(x: pocketLeftX + 62, y: bottomY - 16))
    p.addCurve(to: CGPoint(x: pocketLeftX, y: hemY - 6),
               control1: CGPoint(x: pocketLeftX + 6, y: bottomY - 150),
               control2: CGPoint(x: pocketLeftX - 6, y: hemY + 150))
    p.closeSubpath()
    return p
}

/// How far the back panel's hem sits above the front panel's at the centre.
let mouthDepth: CGFloat = 62

// MARK: - The computer

/// Draws the CRT unit in its own tilted coordinate space.
func drawComputer(_ ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: computerCenter.x, y: computerCenter.y)
    ctx.rotate(by: tilt)

    let w = computerSize.width, h = computerSize.height
    let body = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)

    // Drop shadow behind the case, so it sits off the background
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 42, color: rgb(0, 0, 0, 0.55))
    ctx.fill(roundedRect(body, 46), C.caseMid)
    ctx.restoreGState()

    // Case: lit from upper-left
    ctx.fillLinearGradient(roundedRect(body, 46),
                           [C.caseLight, C.caseMid, C.caseDark],
                           [0, 0.55, 1],
                           from: CGPoint(x: body.minX, y: body.minY),
                           to: CGPoint(x: body.maxX, y: body.maxY))

    // Bezel
    let bezelRect = body.insetBy(dx: 34, dy: 34).offsetBy(dx: 0, dy: -12)
    ctx.fill(roundedRect(bezelRect, 34), C.bezel)

    // Screen
    let screen = bezelRect.insetBy(dx: 18, dy: 18)
    let screenPath = roundedRect(screen, 22)
    ctx.fillRadialGradient(screenPath, [C.screenLit, C.screenDark], [0, 1],
                           center: CGPoint(x: screen.midX, y: screen.midY - 20),
                           radius: screen.width * 0.78)

    // Scanlines
    ctx.saveGState()
    ctx.addPath(screenPath); ctx.clip()
    ctx.setFillColor(rgb(0, 0, 0, 0.20))
    var y = screen.minY
    while y < screen.maxY { ctx.fill(CGRect(x: screen.minX, y: y, width: screen.width, height: 2)); y += 5 }
    ctx.restoreGState()

    // Prompt + cursor + output lines, glowing
    ctx.saveGState()
    ctx.addPath(screenPath); ctx.clip()
    ctx.setShadow(offset: .zero, blur: 26, color: C.phosphor.copy(alpha: 0.95)!)

    let lx = screen.minX + 42
    let promptY = screen.minY + 62
    let chev = CGMutablePath()
    chev.move(to: CGPoint(x: lx, y: promptY))
    chev.addLine(to: CGPoint(x: lx + 46, y: promptY + 34))
    chev.addLine(to: CGPoint(x: lx, y: promptY + 68))
    ctx.stroke(chev, C.phosphor, width: 17)

    ctx.fill(roundedRect(CGRect(x: lx + 72, y: promptY + 2, width: 46, height: 66), 5), C.phosphor)

    let lines: [(CGFloat, CGFloat)] = [(0, 232), (1, 160), (2, 262), (3, 122)]
    for (i, wdt) in lines {
        let ly = promptY + 116 + i * 46
        ctx.stroke(CGPath(roundedRect: CGRect(x: lx + 12, y: ly, width: wdt, height: 18),
                          cornerWidth: 9, cornerHeight: 9, transform: nil),
                   i.truncatingRemainder(dividingBy: 2) == 0 ? C.phosphor : C.phosphorDim,
                   width: 0)
        ctx.fill(CGPath(roundedRect: CGRect(x: lx + 12, y: ly, width: wdt, height: 18),
                        cornerWidth: 9, cornerHeight: 9, transform: nil),
                 i.truncatingRemainder(dividingBy: 2) == 0 ? C.phosphor : C.phosphorDim)
    }
    ctx.restoreGState()

    // Glass highlight sweep
    let gloss = CGMutablePath()
    gloss.move(to: CGPoint(x: screen.minX, y: screen.minY))
    gloss.addLine(to: CGPoint(x: screen.maxX, y: screen.minY))
    gloss.addLine(to: CGPoint(x: screen.minX, y: screen.maxY))
    gloss.closeSubpath()
    ctx.saveGState()
    ctx.addPath(screenPath); ctx.clip()
    ctx.fillLinearGradient(gloss, [rgb(255, 255, 255, 0.10), rgb(255, 255, 255, 0)], [0, 1],
                           from: CGPoint(x: screen.minX, y: screen.minY),
                           to: CGPoint(x: screen.midX, y: screen.maxY))
    ctx.restoreGState()

    ctx.restoreGState()
}

/// Shadow cast by the pocket mouth down onto the computer, and the ambient
/// darkening of the part that is swallowed by the pocket. Clipped to the
/// computer so it never leaks onto the background.
func drawPocketShadowOnComputer(_ ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: computerCenter.x, y: computerCenter.y)
    ctx.rotate(by: tilt)
    let w = computerSize.width, h = computerSize.height
    ctx.addPath(roundedRect(CGRect(x: -w / 2, y: -h / 2, width: w, height: h), 46))
    ctx.clip()
    ctx.rotate(by: -tilt)
    ctx.translateBy(x: -computerCenter.x, y: -computerCenter.y)

    // Ambient occlusion ramping into darkness as it approaches the mouth,
    // then a hard falloff right at the lip where the fabric occludes it.
    let band = CGRect(x: 0, y: hemY - 320, width: S, height: 360)
    ctx.fillLinearGradient(CGPath(rect: band, transform: nil),
                           [rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.18), rgb(0, 0, 0, 0.62), rgb(0, 0, 0, 0.93)],
                           [0, 0.48, 0.80, 1],
                           from: CGPoint(x: 0, y: band.minY), to: CGPoint(x: 0, y: band.maxY))
    ctx.restoreGState()
}

// MARK: - Render

/// iOS 18 wants three renderings of the same icon. The light one is opaque and
/// carries its own background; the other two are drawn on transparency because
/// the system supplies the backdrop (a dark gradient, or the user's tint).
enum Variant: String, CaseIterable {
    case light, dark, tinted

    var filename: String {
        switch self {
        case .light: "icon-1024.png"
        case .dark: "icon-1024-dark.png"
        case .tinted: "icon-1024-tinted.png"
        }
    }

    /// Only the light variant paints its own background.
    var drawsBackground: Bool { self == .light }
}

func render(_ variant: Variant) -> CGImage {
    let alphaInfo: CGImageAlphaInfo = variant.drawsBackground ? .noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: alphaInfo.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Flip to a top-left origin so the geometry above reads like the picture.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)

    if variant.drawsBackground {
        // Background
        ctx.fillLinearGradient(CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil),
                               [C.bgTop, C.bgBottom], [0, 1],
                               from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: S))
        // Soft glow behind the screen
        ctx.fillRadialGradient(CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil),
                               [rgb(64, 200, 120, 0.13), rgb(64, 200, 120, 0)], [0, 1],
                               center: CGPoint(x: 512, y: 390), radius: 430)
    }

    // 1. Back panel of the pocket, behind everything. Its hem rides above the
    //    front hem, so the crescent between the two reads as the pocket mouth.
    let back = pocketPanel(rise: mouthDepth)
    ctx.fillLinearGradient(back, [C.denimShadow, C.pocketInterior], [0, 0.7],
                           from: CGPoint(x: 0, y: hemY - mouthDepth - bulgeLift),
                           to: CGPoint(x: 0, y: hemY + 30))
    // Its own hem catches a sliver of light, so it reads as fabric, not a hole.
    ctx.stroke(hemCurve(rise: mouthDepth), rgb(86, 122, 178, 0.42), width: 5)

    // 2. The computer, dropped in.
    drawComputer(ctx)

    // 3. The pocket mouth's shadow falling on it.
    drawPocketShadowOnComputer(ctx)

    // 4. Front panel of the pocket, over the computer's bottom.
    let front = pocketPanel(rise: 0)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 0, 0.65))
    ctx.fill(front, C.denimMid)
    ctx.restoreGState()

    // Denim shading: lighter where the fabric is stretched over the computer.
    ctx.fillLinearGradient(front, [C.denimLight, C.denimMid, C.denimDark], [0, 0.45, 1],
                           from: CGPoint(x: 0, y: hemY - 40), to: CGPoint(x: 0, y: pocketBottomY))
    ctx.fillRadialGradient(front, [rgb(150, 188, 236, 0.42), rgb(150, 188, 236, 0)], [0, 1],
                           center: CGPoint(x: 512, y: hemY + 26), radius: 300)
    // Corners fall away into shadow.
    ctx.fillRadialGradient(front, [rgb(20, 38, 70, 0), rgb(20, 38, 70, 0.55)], [0.55, 1],
                           center: CGPoint(x: 512, y: hemY + 150), radius: 470)

    // Fabric folds fanning out from the troughs, where a stuffed pocket
    // creases hardest, plus two shallow ones under the bulge itself.
    ctx.saveGState()
    ctx.addPath(front); ctx.clip()
    for (originX, spread, len, alpha) in [
        (bulgeLeftX, -96.0, 176.0, 0.26), (bulgeLeftX, -30.0, 132.0, 0.16),
        (bulgeRightX, 96.0, 176.0, 0.26), (bulgeRightX, 30.0, 132.0, 0.16),
        (512.0 - 64, -18.0, 96.0, 0.12), (512.0 + 64, 18.0, 96.0, 0.12),
    ] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        let f = CGMutablePath()
        f.move(to: CGPoint(x: originX, y: hemY + 14))
        f.addQuadCurve(to: CGPoint(x: originX + spread, y: hemY + len),
                       control: CGPoint(x: originX + spread * 0.35, y: hemY + len * 0.55))
        ctx.stroke(f, rgb(30, 52, 92, alpha), width: 9)
    }
    ctx.restoreGState()

    // Top hem highlight — the lip of the pocket catching light.
    let hemLine = hemCurve(rise: 0)
    ctx.stroke(hemLine, rgb(178, 210, 246, 0.85), width: 7)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: 9)
    ctx.stroke(hemLine, rgb(34, 58, 100, 0.55), width: 6)
    ctx.restoreGState()

    // Golden stitching, following the pocket outline just inside the seam.
    let stitchPath = CGMutablePath()
    let inset: CGFloat = 40
    stitchPath.move(to: CGPoint(x: pocketLeftX + inset, y: hemY + 34))
    stitchPath.addCurve(to: CGPoint(x: pocketLeftX + inset + 22, y: pocketBottomY - 108),
                        control1: CGPoint(x: pocketLeftX + inset - 4, y: hemY + 170),
                        control2: CGPoint(x: pocketLeftX + inset + 2, y: pocketBottomY - 176))
    stitchPath.addCurve(to: CGPoint(x: 512, y: pocketBottomY - 44),
                        control1: CGPoint(x: pocketLeftX + inset + 46, y: pocketBottomY - 58),
                        control2: CGPoint(x: 512 - 132, y: pocketBottomY - 44))
    stitchPath.addCurve(to: CGPoint(x: pocketRightX - inset - 22, y: pocketBottomY - 108),
                        control1: CGPoint(x: 512 + 132, y: pocketBottomY - 44),
                        control2: CGPoint(x: pocketRightX - inset - 46, y: pocketBottomY - 58))
    stitchPath.addCurve(to: CGPoint(x: pocketRightX - inset, y: hemY + 34),
                        control1: CGPoint(x: pocketRightX - inset - 2, y: pocketBottomY - 176),
                        control2: CGPoint(x: pocketRightX - inset + 4, y: hemY + 170))
    ctx.stroke(stitchPath, C.stitch, width: 8, dash: [22, 18], cap: .butt)

    // Studs at the pocket corners.
    for x in [CGFloat(pocketLeftX + 88), CGFloat(pocketRightX - 88)] {
        let c = CGRect(x: x - 17, y: hemY + 96, width: 34, height: 34)
        ctx.fill(CGPath(ellipseIn: c, transform: nil), C.stud)
        ctx.fill(CGPath(ellipseIn: c.insetBy(dx: 10, dy: 10).offsetBy(dx: -3, dy: -3), transform: nil),
                 rgb(252, 226, 158))
    }

    let image = ctx.makeImage()!
    return variant == .light ? image : recolor(image, for: variant)
}

/// Rewrites the rendered pixels for the two system-composited variants.
///
/// Dark: everything is dimmed, but saturated colour is dimmed far less than
/// bright neutral colour — that keeps the phosphor glowing while taking the
/// glare off the cream case, which is the only part that would otherwise
/// shout on a dark home screen.
///
/// Tinted: collapse to luminance, because the system maps grey levels onto the
/// user's chosen tint. Contrast is stretched a little so the art doesn't turn
/// to mush once it's a single hue.
func recolor(_ image: CGImage, for variant: Variant) -> CGImage {
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    for i in stride(from: 0, to: px.count, by: 4) {
        let a = CGFloat(px[i + 3]) / 255
        guard a > 0 else { continue }
        // Un-premultiply so the maths runs on the real colour.
        var r = CGFloat(px[i]) / 255 / a
        var g = CGFloat(px[i + 1]) / 255 / a
        var b = CGFloat(px[i + 2]) / 255 / a

        switch variant {
        case .light:
            break
        case .dark:
            let hi = max(r, g, b), lo = min(r, g, b)
            let saturation = hi > 0 ? (hi - lo) / hi : 0
            let dim = 0.50 + 0.32 * saturation
            r *= dim; g *= dim; b *= dim
        case .tinted:
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            // Stretch hard around mid-grey: the case and the denim otherwise
            // land close together and the whole icon flattens out once it is
            // a single hue. Then lift slightly off pure black.
            let stretched = min(max((luma - 0.48) * 1.5 + 0.5, 0), 1)
            let v = 0.04 + stretched * 0.96
            r = v; g = v; b = v
        }

        px[i] = UInt8(min(max(r, 0), 1) * a * 255)
        px[i + 1] = UInt8(min(max(g, 0), 1) * a * 255)
        px[i + 2] = UInt8(min(max(b, 0), 1) * a * 255)
    }
    return ctx.makeImage()!
}

// MARK: - Write

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "pockterm/Assets.xcassets/AppIcon.appiconset"

for variant in Variant.allCases {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(variant.filename)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        fatalError("cannot open \(url.path) for writing")
    }
    CGImageDestinationAddImage(dest, render(variant), nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed: \(url.path)") }
    print("wrote \(url.path)")
}
