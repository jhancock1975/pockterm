import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// caption <out.png> <width> <height> <rtl:0|1> <text>
let a = CommandLine.arguments
guard a.count >= 6 else { FileHandle.standardError.write("usage\n".data(using:.utf8)!); exit(2) }
let out = URL(fileURLWithPath: a[1])
let W = Int(a[2])!, H = Int(a[3])!
let rtl = a[4] == "1"
let text = a[5]

let boxMargin: CGFloat = 36
let boxW = CGFloat(W) - boxMargin * 2
let corner: CGFloat = 28
let fontSize: CGFloat = 46
// Always the two-line height, so a short caption still covers a tall one
// underneath it in the source video.
let boxH: CGFloat = 190

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(3) }
ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))

let boxY = (CGFloat(H) - boxH) / 2
let boxRect = CGRect(x: boxMargin, y: boxY, width: boxW, height: boxH)
let path = CGPath(roundedRect: boxRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.addPath(path)
ctx.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1.0))
ctx.fillPath()

// System font cascades automatically, which is what carries Telugu,
// Devanagari, CJK, Greek and Cyrillic without naming a font per language.
let base = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
    ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
let desc = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), [
    kCTFontTraitsAttribute: [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitBold.rawValue]
] as CFDictionary)
let font = CTFontCreateWithFontDescriptor(desc, fontSize, nil)

// CoreText's own paragraph style: no AppKit dependency in a CLI tool.
var alignment = CTTextAlignment.center
var direction = rtl ? CTWritingDirection.rightToLeft : .leftToRight
var spacing: CGFloat = 6
let settings = [
    CTParagraphStyleSetting(spec: .alignment,
                            valueSize: MemoryLayout<CTTextAlignment>.size, value: &alignment),
    CTParagraphStyleSetting(spec: .baseWritingDirection,
                            valueSize: MemoryLayout<CTWritingDirection>.size, value: &direction),
    CTParagraphStyleSetting(spec: .lineSpacingAdjustment,
                            valueSize: MemoryLayout<CGFloat>.size, value: &spacing),
]
let para = CTParagraphStyleCreate(settings, settings.count)

let attr = NSAttributedString(string: text, attributes: [
    kCTFontAttributeName as NSAttributedString.Key: font,
    kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
    kCTParagraphStyleAttributeName as NSAttributedString.Key: para,
])

let inset: CGFloat = 34
let textRect = boxRect.insetBy(dx: inset, dy: 12)
let setter = CTFramesetterCreateWithAttributedString(attr)
var fit = CFRange()
let size = CTFramesetterSuggestFrameSizeWithConstraints(
    setter, CFRange(location: 0, length: 0), nil,
    CGSize(width: textRect.width, height: .greatestFiniteMagnitude), &fit)
let drawRect = CGRect(x: textRect.minX,
                      y: boxRect.midY - size.height / 2,
                      width: textRect.width, height: size.height)
let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                     CGPath(rect: drawRect, transform: nil), nil)
CTFrameDraw(frame, ctx)

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(4) }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
