#include <metal_stdlib>
using namespace metal;

struct GlyphUniforms {
    float2 viewport;
    float progress;
    float particleSize;
    float4 blend;
};

struct GlyphTile {
    float2 source;
    float2 destination;
    float2 bend;
    float2 size;
    float4 textureWindow;
    float4 timing;
    float4 cloud;
};

struct GlyphRaster {
    float4 position [[position]];
    float2 uv;
    float visibility;
};

vertex GlyphRaster balanceGlyphVertex(uint vertexID [[vertex_id]],
                                      uint instanceID [[instance_id]],
                                      constant GlyphTile *tiles [[buffer(0)]],
                                      constant GlyphUniforms &frame [[buffer(1)]]) {
    const float2 corners[] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };
    const GlyphTile tile = tiles[instanceID];
    const float2 corner = corners[vertexID];

    const float timeline = tile.cloud.w >= 0
        ? frame.progress / frame.blend.y
        : frame.progress;
    const float local = clamp((timeline - tile.timing.x) / tile.timing.w, 0.0, 1.0);
    const float cubic = local * local * (3.0 - 2.0 * local);
    const float quintic = local * local * local
        * (local * (local * 6.0 - 15.0) + 10.0);
    const float eased = frame.blend.z < 0.5
        ? mix(local, cubic, frame.blend.z * 2.0)
        : mix(cubic, quintic, (frame.blend.z - 0.5) * 2.0);

    const float handoff = clamp(
        (frame.progress - frame.blend.x) / (frame.blend.y - frame.blend.x),
        0.0, 1.0
    );
    const float cloudMix = handoff * handoff * handoff
        * (handoff * (handoff * 6.0 - 15.0) + 10.0);

    const float2 center = mix(tile.source, tile.destination, eased)
        + tile.bend * sin(eased * M_PI_F);
    float2 size = mix(tile.size, float2(frame.particleSize * tile.timing.y), eased);
    if (tile.cloud.w >= 0) {
        size = mix(size, float2(tile.cloud.z), cloudMix);
    }

    const float angle = sin(eased * M_PI_F) * tile.timing.z;
    float2 offset = (corner - 0.5) * size;
    offset = float2(
        offset.x * cos(angle) - offset.y * sin(angle),
        offset.x * sin(angle) + offset.y * cos(angle)
    );
    const float2 point = center + offset;

    GlyphRaster output;
    output.position = float4(point.x / frame.viewport.x * 2.0 - 1.0,
                             1.0 - point.y / frame.viewport.y * 2.0, 0.0, 1.0);
    output.uv = tile.textureWindow.xy + corner * tile.textureWindow.zw;
    output.visibility = (1.0 - cloudMix)
        * (tile.cloud.w >= 0 ? mix(1.0, tile.cloud.w, cloudMix) : 1.0);
    return output;
}

fragment float4 balanceGlyphFragment(GlyphRaster raster [[stage_in]],
                                     texture2d<float> glyphImage [[texture(0)]]) {
    constexpr sampler glyphSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    filter::linear);
    return glyphImage.sample(glyphSampler, raster.uv) * raster.visibility;
}

struct DustUniforms {
    float2 viewport;
    float opacity;
    float padding;
};

struct DustPoint {
    float2 position;
    float radius;
    float opacity;
    float4 color;
};

struct DustRaster {
    float4 position [[position]];
    float2 local [[sample_no_perspective]];
    float opacity [[flat]];
    float4 color [[flat]];
};

vertex DustRaster balanceDustVertex(uint vertexID [[vertex_id]],
                                    uint instanceID [[instance_id]],
                                    constant DustPoint *points [[buffer(0)]],
                                    constant DustUniforms &frame [[buffer(1)]]) {
    constexpr float2 corners[] = {
        float2(-1, -1), float2(1, -1),
        float2(-1, 1), float2(1, 1)
    };
    const DustPoint particle = points[instanceID];
    const float2 local = corners[vertexID];
    const float2 point = particle.position + local * particle.radius;

    DustRaster output;
    output.position = float4(point.x / frame.viewport.x * 2.0 - 1.0,
                             1.0 - point.y / frame.viewport.y * 2.0,
                             1.0 - particle.opacity * 0.9, 1.0);
    output.local = local;
    output.opacity = particle.opacity * frame.opacity;
    output.color = particle.color;
    return output;
}

fragment float4 balanceDustFragment(DustRaster raster [[stage_in]]) {
    if (dot(raster.local, raster.local) > 1.0) {
        discard_fragment();
    }
    const float alpha = raster.color.a * raster.opacity;
    return float4(raster.color.rgb * alpha, alpha);
}
