import AppKit
import CoreText
import Metal

struct Glyph {
    var u: UInt16 = 0
    var v: UInt16 = 0
    var width: UInt16 = 0
    var height: UInt16 = 0
    /// Offset from the cell's top-left corner to the bitmap's.
    var left: Int16 = 0
    var top: Int16 = 0
    var isColor = false

    var isEmpty: Bool { width == 0 }
}

/// A shelf-packed texture. Glyphs in a terminal cluster around a few heights, so
/// shelves waste little space and insertion stays O(shelves).
final class Atlas {
    let texture: MTLTexture
    let size: Int

    private struct Shelf {
        var y: Int
        var height: Int
        var x: Int
    }

    private var shelves: [Shelf] = []
    private var nextY = 0

    init(device: MTLDevice, size: Int, format: MTLPixelFormat) {
        self.size = size
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        texture = device.makeTexture(descriptor: descriptor)!
    }

    func reset() {
        shelves.removeAll()
        nextY = 0
    }

    func insert(width: Int, height: Int, bytes: UnsafeRawPointer, bytesPerRow: Int) -> (x: Int, y: Int)? {
        for index in shelves.indices {
            let shelf = shelves[index]
            let fits = height <= shelf.height && height * 4 >= shelf.height * 3
            if fits && shelf.x + width <= size {
                shelves[index].x += width
                upload(x: shelf.x, y: shelf.y, width: width, height: height, bytes: bytes, bytesPerRow: bytesPerRow)
                return (shelf.x, shelf.y)
            }
        }
        guard nextY + height <= size, width <= size else { return nil }
        shelves.append(Shelf(y: nextY, height: height, x: width))
        let y = nextY
        nextY += height
        upload(x: 0, y: y, width: width, height: height, bytes: bytes, bytesPerRow: bytesPerRow)
        return (0, y)
    }

    private func upload(x: Int, y: Int, width: Int, height: Int, bytes: UnsafeRawPointer, bytesPerRow: Int) {
        texture.replace(region: MTLRegionMake2D(x, y, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: bytesPerRow)
    }
}

/// Rasterises text with Core Text and caches it in the atlases. Everything here
/// is in device pixels.
final class GlyphCache {
    enum Style {
        static let bold = 1
        static let italic = 2
    }

    let cellWidth: Int
    let cellHeight: Int
    let baseline: Int
    let underlineThickness: Int
    let mask: Atlas
    let color: Atlas

    /// Bumped when the atlases are reset, which invalidates every cached row.
    private(set) var generation = 0

    private let fonts: [CTFont]
    private let symbols: CTFont?
    private var ascii = [Glyph?](repeating: nil, count: 128 * 4)
    private var scalars: [UInt64: Glyph] = [:]
    private var clusters: [String: Glyph] = [:]

    init(device: MTLDevice, family: String?, pointSize: CGFloat, scale: CGFloat) {
        let pixelSize = pointSize * scale
        let regular: CTFont
        let bold: CTFont
        if let family, !family.isEmpty {
            regular = CTFontCreateWithName(family as CFString, pixelSize, nil)
            bold = CTFontCreateCopyWithSymbolicTraits(regular, 0, nil, .boldTrait, .boldTrait) ?? regular
        } else {
            regular = NSFont.monospacedSystemFont(ofSize: pixelSize, weight: .regular)
            bold = NSFont.monospacedSystemFont(ofSize: pixelSize, weight: .bold)
        }
        let italic = CTFontCreateCopyWithSymbolicTraits(regular, 0, nil, .italicTrait, .italicTrait) ?? regular
        let boldItalic = CTFontCreateCopyWithSymbolicTraits(bold, 0, nil, .italicTrait, .italicTrait) ?? bold
        fonts = [regular, bold, italic, boldItalic]
        symbols = Self.loadSymbolsFont(size: pixelSize)

        var character = UniChar(UnicodeScalar("M").value)
        var glyph = CGGlyph(0)
        CTFontGetGlyphsForCharacters(regular, &character, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(regular, .horizontal, &glyph, &advance, 1)

        let ascent = CTFontGetAscent(regular)
        let descent = CTFontGetDescent(regular)
        let leading = CTFontGetLeading(regular)
        cellWidth = Int(advance.width.rounded(.up))
        cellHeight = max(Int((ascent + descent + leading).rounded(.up)), Int((pixelSize * 1.2).rounded()))
        baseline = Int(((CGFloat(cellHeight) - ascent - descent) / 2 + ascent).rounded())
        underlineThickness = max(1, Int(CTFontGetUnderlineThickness(regular).rounded()))

        mask = Atlas(device: device, size: 2048, format: .r8Unorm)
        color = Atlas(device: device, size: 2048, format: .bgra8Unorm)
    }

    private static func loadSymbolsFont(size: CGFloat) -> CTFont? {
        let name = "JetBrainsMonoNerdFont-Regular.ttf"
        var candidates = [Bundle.main.resourceURL?.appendingPathComponent(name)]
        // An unbundled development build runs straight out of .build.
        var directory = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/")
        for _ in 0..<4 {
            candidates.append(directory.appendingPathComponent("vendor/ghostty-src/src/font/res/\(name)"))
            directory = directory.deletingLastPathComponent()
        }
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url),
                  let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData) else { continue }
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }
        return nil
    }

    @inline(__always)
    func glyph(codepoint: UInt32, style: Int) -> Glyph {
        if codepoint < 128 {
            let index = Int(codepoint) * 4 + style
            if let cached = ascii[index] { return cached }
            let made = make(codepoint: codepoint, style: style)
            ascii[index] = made
            return made
        }
        let key = UInt64(codepoint) << 2 | UInt64(style)
        if let cached = scalars[key] { return cached }
        let made = make(codepoint: codepoint, style: style)
        scalars[key] = made
        return made
    }

    func glyph(cluster: [UInt32], style: Int) -> Glyph {
        let text = String(String.UnicodeScalarView(cluster.compactMap(UnicodeScalar.init)))
        let key = "\(style)\(text)"
        if let cached = clusters[key] { return cached }
        let made = rasterize(text, font: fonts[style])
        clusters[key] = made
        return made
    }

    private func make(codepoint: UInt32, style: Int) -> Glyph {
        if BoxDrawing.handles(codepoint) {
            return rasterizeBox(codepoint)
        }
        guard let scalar = UnicodeScalar(codepoint) else { return Glyph() }
        // Private-use characters mean nothing to the system's font fallback, so
        // the icons shell prompts rely on go straight to the bundled symbols font.
        if let symbols, Self.isPrivateUse(codepoint) {
            return rasterize(String(Character(scalar)), font: symbols)
        }
        return rasterize(String(Character(scalar)), font: fonts[style])
    }

    private static func isPrivateUse(_ codepoint: UInt32) -> Bool {
        (0xE000...0xF8FF).contains(codepoint) || (0xF0000...0xFFFFD).contains(codepoint)
    }

    private func rasterizeBox(_ codepoint: UInt32) -> Glyph {
        var pixels = [UInt8](repeating: 0, count: cellWidth * cellHeight)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: cellWidth, height: cellHeight, bitsPerComponent: 8,
                bytesPerRow: cellWidth, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.setStrokeColor(gray: 1, alpha: 1)
            context.translateBy(x: 0, y: CGFloat(cellHeight))
            context.scaleBy(x: 1, y: -1)
            BoxDrawing.draw(codepoint, in: context, width: cellWidth, height: cellHeight)
            return true
        }
        guard drawn else { return Glyph() }
        return store(pixels: pixels, width: cellWidth, height: cellHeight, left: 0, top: 0, isColor: false)
    }

    private func rasterize(_ text: String, font: CTFont) -> Glyph {
        // Without this attribute Core Text draws in black, whatever the context's
        // fill colour is, and the white-on-black mask comes out empty.
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: true,
        ]
        guard let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else {
            return Glyph()
        }
        let line = CTLineCreateWithAttributedString(string)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let isColor = runs.contains { run in
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = runAttributes[kCTFontAttributeName] else { return false }
            return CTFontGetSymbolicTraits(value as! CTFont).contains(.traitColorGlyphs)
        }

        var bounds = CTLineGetBoundsWithOptions(line, isColor ? [] : .useGlyphPathBounds)
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return Glyph() }

        // Colour glyphs are drawn at a fixed size and would otherwise overflow.
        var scale: CGFloat = 1
        if isColor {
            scale = min(1, CGFloat(cellWidth * 2) / bounds.width, CGFloat(cellHeight) / bounds.height)
            bounds = bounds.applying(CGAffineTransform(scaleX: scale, y: scale))
        }

        let left = Int(bounds.minX.rounded(.down)) - 1
        let right = Int(bounds.maxX.rounded(.up)) + 1
        let bottom = Int(bounds.minY.rounded(.down)) - 1
        let top = Int(bounds.maxY.rounded(.up)) + 1
        let width = right - left
        let height = top - bottom
        guard width > 0, height > 0, width < 1024, height < 1024 else { return Glyph() }

        let bytesPerPixel = isColor ? 4 : 1
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            let space = isColor ? CGColorSpace(name: CGColorSpace.sRGB)! : CGColorSpaceCreateDeviceGray()
            let info = isColor
                ? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                : CGImageAlphaInfo.none.rawValue
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: space, bitmapInfo: info) else { return false }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setShouldSmoothFonts(false)
            context.setFillColor(gray: 1, alpha: 1)
            context.translateBy(x: CGFloat(-left), y: CGFloat(-bottom))
            context.scaleBy(x: scale, y: scale)
            context.textPosition = .zero
            CTLineDraw(line, context)
            return true
        }
        guard drawn else { return Glyph() }

        let cellTop = isColor ? (cellHeight - height) / 2 : baseline - top
        return store(pixels: pixels, width: width, height: height, left: left, top: cellTop, isColor: isColor)
    }

    private func store(pixels: [UInt8], width: Int, height: Int, left: Int, top: Int, isColor: Bool) -> Glyph {
        let atlas = isColor ? color : mask
        let bytesPerRow = width * (isColor ? 4 : 1)
        var slot = pixels.withUnsafeBytes {
            atlas.insert(width: width, height: height, bytes: $0.baseAddress!, bytesPerRow: bytesPerRow)
        }
        if slot == nil {
            // Rows that were built against the old layout get rebuilt next frame.
            evictAll()
            slot = pixels.withUnsafeBytes {
                atlas.insert(width: width, height: height, bytes: $0.baseAddress!, bytesPerRow: bytesPerRow)
            }
        }
        guard let slot else { return Glyph() }
        return Glyph(u: UInt16(slot.x), v: UInt16(slot.y), width: UInt16(width), height: UInt16(height),
                     left: Int16(left), top: Int16(top), isColor: isColor)
    }

    private func evictAll() {
        mask.reset()
        color.reset()
        ascii = [Glyph?](repeating: nil, count: 128 * 4)
        scalars.removeAll()
        clusters.removeAll()
        generation += 1
    }
}
