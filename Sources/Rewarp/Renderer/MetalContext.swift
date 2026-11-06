import Foundation
import Metal

/// One quad. Every pass shares this layout, so a frame is just a few flat arrays.
/// Keep in sync with `Instance` in the shader source below.
struct Instance {
    var x: Int16
    var y: Int16
    var width: UInt16
    var height: UInt16
    var u: UInt16 = 0
    var v: UInt16 = 0
    var color: UInt32
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Instance {
    packed_short2 position;
    packed_ushort2 size;
    packed_ushort2 uv;
    packed_uchar4 color;
};

struct Uniforms {
    float2 viewport;
    float2 atlasSize;
};

struct Fragment {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex Fragment quadVertex(uint vertexId [[vertex_id]],
                     uint instanceId [[instance_id]],
                     constant Instance *instances [[buffer(0)]],
                     constant Uniforms &uniforms [[buffer(1)]]) {
    Instance instance = instances[instanceId];
    float2 corner = float2(vertexId & 1, vertexId >> 1);
    float2 size = float2(ushort2(instance.size));
    float2 pixel = float2(short2(instance.position)) + corner * size;
    Fragment out;
    out.position = float4(pixel.x / uniforms.viewport.x * 2.0 - 1.0,
                          1.0 - pixel.y / uniforms.viewport.y * 2.0,
                          0.0, 1.0);
    out.uv = (float2(ushort2(instance.uv)) + corner * size) / uniforms.atlasSize;
    out.color = float4(uchar4(instance.color)) / 255.0;
    return out;
}

fragment float4 solid(Fragment in [[stage_in]]) {
    return float4(in.color.rgb * in.color.a, in.color.a);
}

fragment float4 maskedText(Fragment in [[stage_in]],
                           texture2d<float> atlas [[texture(0)]],
                           sampler pointSampler [[sampler(0)]]) {
    float alpha = atlas.sample(pointSampler, in.uv).r * in.color.a;
    return float4(in.color.rgb * alpha, alpha);
}

fragment float4 colorText(Fragment in [[stage_in]],
                          texture2d<float> atlas [[texture(0)]],
                          sampler pointSampler [[sampler(0)]]) {
    return atlas.sample(pointSampler, in.uv) * in.color.a;
}
"""

/// The device-wide GPU objects, shared by every pane.
final class MetalContext {
    static let shared = MetalContext()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let solid: MTLRenderPipelineState
    let maskedText: MTLRenderPipelineState
    let colorText: MTLRenderPipelineState
    let sampler: MTLSamplerState

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal is not available")
        }
        self.device = device
        self.queue = queue

        // Compiled at runtime because the `metal` tool needs a full Xcode.
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            fatalError("shader compile failed: \(error)")
        }

        func pipeline(_ fragment: String) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "quadVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = .bgra8Unorm
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                fatalError("pipeline \(fragment) failed: \(error)")
            }
        }
        solid = pipeline("solid")
        maskedText = pipeline("maskedText")
        colorText = pipeline("colorText")

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
    }
}
