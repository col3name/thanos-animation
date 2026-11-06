// Adapted from Telegram-iOS DustFluidShaders.metal, stable fluids GPU solver.
#include <metal_stdlib>
using namespace metal;
struct DustFluidSplat { float2 position; float2 force; float radius; float padding; };
struct DustFluidParams { float timeStep; float velocityDissipation; float pressureScale; };
static inline bool dustFluidIsOutside(texture2d<half, access::write> texture, uint2 gid) {
    return gid.x >= texture.get_width() || gid.y >= texture.get_height();
}
static inline half4 dustFluidRead(texture2d<half, access::read> texture, int2 position) {
    int2 maxPosition = int2(texture.get_width(), texture.get_height()) - 1;
    return texture.read(uint2(clamp(position, int2(0), maxPosition)));
}
kernel void dustFluidClear(texture2d<float, access::write> output [[ texture(0) ]],
                           uint2 gid [[ thread_position_in_grid ]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    output.write(float4(0.0), gid);
}
kernel void dustFluidSplat(
    texture2d<half, access::read> velocityIn [[ texture(0) ]],
    texture2d<half, access::write> velocityOut [[ texture(1) ]],
    const device DustFluidSplat *splats [[ buffer(0) ]],
    const device uint &splatCount [[ buffer(1) ]],
    uint2 gid [[ thread_position_in_grid ]]) {
    if (dustFluidIsOutside(velocityOut, gid)) return;
    float2 position = float2(gid) + 0.5;
    float2 velocity = float2(velocityIn.read(gid).xy);
    for (uint i = 0; i < splatCount; i++) {
        DustFluidSplat splat = splats[i];
        float2 delta = position - splat.position;
        velocity += splat.force * exp(-dot(delta, delta) / (splat.radius * splat.radius));
    }
    velocityOut.write(half4(half2(velocity), 0.0, 0.0), gid);
}
kernel void dustFluidCurl(texture2d<half, access::read> velocity [[ texture(0) ]],
                          texture2d<half, access::write> curlOut [[ texture(1) ]],
                          uint2 gid [[ thread_position_in_grid ]]) {
    if (dustFluidIsOutside(curlOut, gid)) return;
    int2 position = int2(gid);
    float left = dustFluidRead(velocity, position + int2(-1, 0)).y;
    float right = dustFluidRead(velocity, position + int2(1, 0)).y;
    float bottom = dustFluidRead(velocity, position + int2(0, -1)).x;
    float top = dustFluidRead(velocity, position + int2(0, 1)).x;
    float curl = 0.5 * ((right - left) - (top - bottom));
    curlOut.write(half4(curl, 0.0, 0.0, 0.0), gid);
}
kernel void dustFluidDivergence(texture2d<half, access::read> velocity [[ texture(0) ]],
                                texture2d<half, access::write> divergenceOut [[ texture(1) ]],
                                uint2 gid [[ thread_position_in_grid ]]) {
    if (dustFluidIsOutside(divergenceOut, gid)) return;
    int2 position = int2(gid);
    int2 maxPosition = int2(velocity.get_width(), velocity.get_height()) - 1;
    float2 center = float2(velocity.read(gid).xy);
    float left = position.x > 0 ? dustFluidRead(velocity, position + int2(-1, 0)).x : -center.x;
    float right = position.x < maxPosition.x ? dustFluidRead(velocity, position + int2(1, 0)).x : -center.x;
    float bottom = position.y > 0 ? dustFluidRead(velocity, position + int2(0, -1)).y : -center.y;
    float top = position.y < maxPosition.y ? dustFluidRead(velocity, position + int2(0, 1)).y : -center.y;
    float divergence = 0.5 * ((right - left) + (top - bottom));
    divergenceOut.write(half4(divergence, 0.0, 0.0, 0.0), gid);
}
kernel void dustFluidPressure(
    texture2d<half, access::read> pressureIn [[ texture(0) ]],
    texture2d<half, access::read> divergence [[ texture(1) ]],
    texture2d<half, access::write> pressureOut [[ texture(2) ]],
    const device DustFluidParams &params [[ buffer(0) ]],
    uint2 gid [[ thread_position_in_grid ]]) {
    if (dustFluidIsOutside(pressureOut, gid)) return;
    int2 position = int2(gid);
    float left = dustFluidRead(pressureIn, position + int2(-1, 0)).x;
    float right = dustFluidRead(pressureIn, position + int2(1, 0)).x;
    float bottom = dustFluidRead(pressureIn, position + int2(0, -1)).x;
    float top = dustFluidRead(pressureIn, position + int2(0, 1)).x;
    float pressure = ((left + right + bottom + top) * params.pressureScale - float(divergence.read(gid).x)) * 0.25;
    pressureOut.write(half4(pressure, 0.0, 0.0, 0.0), gid);
}
kernel void dustFluidGradientSubtract(
    texture2d<half, access::read> pressure [[ texture(0) ]],
    texture2d<half, access::read> velocityIn [[ texture(1) ]],
    texture2d<half, access::write> velocityOut [[ texture(2) ]],
    uint2 gid [[ thread_position_in_grid ]]) {
    if (dustFluidIsOutside(velocityOut, gid)) return;
    int2 position = int2(gid);
    float left = dustFluidRead(pressure, position + int2(-1, 0)).x;
    float right = dustFluidRead(pressure, position + int2(1, 0)).x;
    float bottom = dustFluidRead(pressure, position + int2(0, -1)).x;
    float top = dustFluidRead(pressure, position + int2(0, 1)).x;
    float2 velocity = float2(velocityIn.read(gid).xy) - 0.5 * float2(right - left, top - bottom);
    velocityOut.write(half4(half2(velocity), 0.0, 0.0), gid);
}
kernel void dustFluidStreamFunction(
    texture2d<float, access::read> streamFunctionIn [[ texture(0) ]],
    texture2d<half, access::read> curl [[ texture(1) ]],
    texture2d<float, access::write> streamFunctionOut [[ texture(2) ]],
    uint2 gid [[ thread_position_in_grid ]]) {
    if (gid.x >= streamFunctionOut.get_width() || gid.y >= streamFunctionOut.get_height()) return;
    uint2 maxPosition = uint2(streamFunctionIn.get_width(), streamFunctionIn.get_height()) - 1;
    float left = gid.x > 0 ? streamFunctionIn.read(gid - uint2(1, 0)).x : 0.0;
    float right = gid.x < maxPosition.x ? streamFunctionIn.read(gid + uint2(1, 0)).x : 0.0;
    float bottom = gid.y > 0 ? streamFunctionIn.read(gid - uint2(0, 1)).x : 0.0;
    float top = gid.y < maxPosition.y ? streamFunctionIn.read(gid + uint2(0, 1)).x : 0.0;
    float streamFunction = (left + right + bottom + top + float(curl.read(gid).x)) * 0.25;
    streamFunctionOut.write(float4(streamFunction, 0.0, 0.0, 0.0), gid);
}
kernel void dustFluidAdvect(
    texture2d<half, access::sample> velocityIn [[ texture(0) ]],
    texture2d<half, access::write> velocityOut [[ texture(1) ]],
    const device DustFluidParams &params [[ buffer(0) ]],
    uint2 gid [[ thread_position_in_grid ]]) {
    if (dustFluidIsOutside(velocityOut, gid)) return;
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 gridSize = float2(velocityOut.get_width(), velocityOut.get_height());
    float2 position = float2(gid) + 0.5;
    float2 velocity = float2(velocityIn.read(gid).xy);
    float2 sourcePosition = position - velocity * params.timeStep;
    float2 advected = float2(velocityIn.sample(linearSampler, sourcePosition / gridSize).xy);
    advected /= 1.0 + params.velocityDissipation * params.timeStep;
    velocityOut.write(half4(half2(advected), 0.0, 0.0), gid);
}
