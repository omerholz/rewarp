import AppKit
import Metal
import QuartzCore
import RewarpCore

/// The instances for one frame.
final class Frame {
    enum Pass {
        case solid
        case text
        case colorText
        case chromeText
    }

    /// Every layer in draw order. The overlay layers come last, for chrome that
    /// floats over the block list.
    static let layers: [(path: ReferenceWritableKeyPath<Frame, [Instance]>, pass: Pass)] = [
        (\.background, .solid),
        (\.text, .text),
        (\.colorText, .colorText),
        (\.decoration, .solid),
        (\.chromeText, .chromeText),
        (\.overlay, .solid),
        (\.overlayText, .text),
        (\.overlayChromeText, .chromeText),
    ]

    var background: [Instance] = []
    var text: [Instance] = []
    var colorText: [Instance] = []
    var decoration: [Instance] = []
    var chromeText: [Instance] = []
    var overlay: [Instance] = []
    var overlayText: [Instance] = []
    var overlayChromeText: [Instance] = []

    func reset() {
        for layer in Self.layers { self[keyPath: layer.path].removeAll(keepingCapacity: true) }
    }

    @inline(__always)
    func append(_ source: [Instance], to path: ReferenceWritableKeyPath<Frame, [Instance]>, x: Int, y: Int) {
        guard !source.isEmpty else { return }
        let start = self[keyPath: path].count
        self[keyPath: path].append(contentsOf: source)
        let dx = Int16(truncatingIfNeeded: x)
        let dy = Int16(truncatingIfNeeded: y)
        self[keyPath: path].withUnsafeMutableBufferPointer { instances in
            for index in start..<instances.count {
                instances[index].x &+= dx
                instances[index].y &+= dy
            }
        }
    }

    func recolorText(cellLeft: Int, cellTop: Int, cellWidth: Int, cellHeight: Int, color: UInt32) {
        let bottom = cellTop + cellHeight
        for index in text.indices {
            let x = Int(text[index].x)
            let y = Int(text[index].y)
            if x >= cellLeft && x < cellLeft + cellWidth && y >= cellTop && y < bottom {
                text[index].color = color
            }
        }
    }
}

extension GlyphCache {
    /// Appends a run of text starting at a cell's top-left corner, stopping with
    /// an ellipsis at `limit`. Returns the x position after the last character.
    @discardableResult
    func emit(_ string: String, x: Int, top: Int, color: UInt32, style: Int = 0,
              limit: Int = .max, into list: inout [Instance]) -> Int {
        // Instance positions are 16-bit, and the header of a tall block can sit far
        // beyond that range. Text that far away isn't visible anyway.
        guard top > -cellHeight * 2, top < Int(Int16.max) - cellHeight * 2 else { return x }
        var cursor = x
        for scalar in string.unicodeScalars {
            let advance = cellWidth * Self.cells(for: scalar)
            if cursor + advance > limit {
                let dots = glyph(codepoint: 0x2026, style: style)
                list.append(Instance(x: Int16(cursor + Int(dots.left)), y: Int16(top + Int(dots.top)),
                                     width: dots.width, height: dots.height, u: dots.u, v: dots.v, color: color))
                return cursor + cellWidth
            }
            let shape = glyph(codepoint: scalar.value, style: style)
            if !shape.isEmpty, !shape.isColor {
                list.append(Instance(x: Int16(cursor + Int(shape.left)), y: Int16(top + Int(shape.top)),
                                     width: shape.width, height: shape.height, u: shape.u, v: shape.v, color: color))
            }
            cursor += advance
        }
        return cursor
    }

    static func cells(for scalar: Unicode.Scalar) -> Int {
        max(1, CellWidth.of(scalar))
    }
}

/// Presents frames to one pane's layer, keeping up to three in flight.
final class PaneRenderer {
    private struct Uniforms {
        var viewport: SIMD2<Float>
        var atlasSize: SIMD2<Float>
    }

    let layer: CAMetalLayer

    private let context = MetalContext.shared
    private let inFlight = DispatchSemaphore(value: 3)
    private var buffers: [MTLBuffer?] = [nil, nil, nil]
    private var bufferIndex = 0

    init(layer: CAMetalLayer) {
        self.layer = layer
        layer.device = context.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 3
        layer.displaySyncEnabled = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = true
    }

    func draw(_ frame: Frame, glyphs: GlyphCache, chromeGlyphs: GlyphCache, clear: RGB) {
        inFlight.wait()
        guard let drawable = layer.nextDrawable(),
              let commands = context.queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        encode(frame, glyphs: glyphs, chromeGlyphs: chromeGlyphs, clear: clear,
               target: drawable.texture, commands: commands)
        commands.present(drawable)
        let semaphore = inFlight
        commands.addCompletedHandler { _ in semaphore.signal() }
        commands.commit()
    }

    #if DEBUG || REWARP_TESTING
    /// Renders off screen and returns the pixels, for debug captures.
    func capture(_ frame: Frame, glyphs: GlyphCache, chromeGlyphs: GlyphCache, clear: RGB,
                 width: Int, height: Int) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: descriptor),
              let commands = context.queue.makeCommandBuffer() else { return nil }
        encode(frame, glyphs: glyphs, chromeGlyphs: chromeGlyphs, clear: clear,
               target: texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    #endif

    private func encode(_ frame: Frame, glyphs: GlyphCache, chromeGlyphs: GlyphCache, clear: RGB,
                        target: MTLTexture, commands: MTLCommandBuffer) {
        let stride = MemoryLayout<Instance>.stride
        let count = Frame.layers.reduce(0) { $0 + frame[keyPath: $1.path].count }
        let needed = max(count, 1) * stride

        if (buffers[bufferIndex]?.length ?? 0) < needed {
            buffers[bufferIndex] = context.device.makeBuffer(length: needed * 2, options: .storageModeShared)
        }
        guard let buffer = buffers[bufferIndex] else { return }
        bufferIndex = (bufferIndex + 1) % buffers.count

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(clear.r) / 255, green: Double(clear.g) / 255, blue: Double(clear.b) / 255, alpha: 1)

        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = Uniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)),
            atlasSize: SIMD2(Float(glyphs.mask.size), Float(glyphs.mask.size)))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentSamplerState(context.sampler, index: 0)

        let contents = buffer.contents().assumingMemoryBound(to: Instance.self)
        var offset = 0
        for layer in Frame.layers {
            let instances = frame[keyPath: layer.path]
            guard !instances.isEmpty else { continue }
            instances.withUnsafeBufferPointer { source in
                (contents + offset).update(from: source.baseAddress!, count: source.count)
            }

            switch layer.pass {
            case .solid:
                encoder.setRenderPipelineState(context.solid)
            case .text:
                encoder.setRenderPipelineState(context.maskedText)
                encoder.setFragmentTexture(glyphs.mask.texture, index: 0)
            case .colorText:
                encoder.setRenderPipelineState(context.colorText)
                encoder.setFragmentTexture(glyphs.color.texture, index: 0)
            case .chromeText:
                encoder.setRenderPipelineState(context.maskedText)
                encoder.setFragmentTexture(chromeGlyphs.mask.texture, index: 0)
            }
            encoder.setVertexBuffer(buffer, offset: offset * stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
            offset += instances.count
        }
        encoder.endEncoding()
    }
}
