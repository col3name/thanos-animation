// Adapted from Telegram-iOS's DustEffectShaders.metal (TelegramMessenger/Telegram-iOS).
// Identical particle motion, sweep, lifetime, glitter and bloom shader math.
#include <metal_stdlib>
#include "loki_header.metal"
using namespace metal;
struct Rectangle { float2 origin; float2 size; };
constant static float2 quadVertices[6] = {
    float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
    float2(1.0, 0.0), float2(0.0, 1.0), float2(1.0, 1.0)
};
struct QuadVertexOut {
    float4 position [[position]];
    float2 uv;
    float alpha;
    float2 local;
    float roundness;
    float grainRadius;
    float glint;
    float bloom;
};
float2 mapLocalToScreenCoordinates(const device Rectangle &rect, const device float2 &size, float2 position) {
    float2 result = float2(rect.origin.x + position.x / size.x * rect.size.x,
                           rect.origin.y + position.y / size.y * rect.size.y);
    return -1.0 + result * 2.0;
}
struct Particle {
    packed_float2 offsetFromBasePosition;
    packed_float2 velocity;
    float lifetime;
    float age;
    packed_float2 displacement;
};
static inline uint dustHash(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}
static inline float dustRandom(uint particleId, uint salt) {
    return float(dustHash(particleId * 0x9e3779b9u + salt) >> 8) * (1.0 / 16777216.0);
}
float noise(float2 p);
kernel void dustEffectInitializeParticle(
    device Particle *particles [[ buffer(0) ]],
    const device float &verticalDirection [[ buffer(1) ]],
    const device uint2 &size [[ buffer(2) ]],
    uint gid [[ thread_position_in_grid ]]
) {
    if (gid >= size.x * size.y) return;
    Loki rng = Loki(gid);
    Particle particle;
    particle.offsetFromBasePosition = packed_float2(0.0, 0.0);
    particle.age = 0.0;
    particle.displacement = packed_float2(0.0, 0.0);
    float direction = rng.rand() * (3.14159265 * 2.0);
    float velocity = 15.0 + rng.rand() * 20.0;
    float2 initialVelocity = float2(cos(direction) * velocity, sin(direction) * velocity);
    initialVelocity.y *= verticalDirection;
    particle.velocity = packed_float2(initialVelocity);
    float2 basePosition = float2(gid % size.x, gid / size.x);
    float pattern = noise(basePosition / 14.0) + 0.5 * noise(basePosition / 6.0 + 17.0);
    particle.lifetime = 2.0 + 1.8 * smoothstep(-0.45, 0.45, pattern) + rng.rand() * 0.3;
    particles[gid] = particle;
}
float particleEaseInWindowFunction(float t) { return t; }
float particleEaseInValueAt(float fraction, float t) {
    float windowSize = 0.8;
    float windowPosition = (1.0 - fraction) * -windowSize + fraction * 1.0;
    float windowT = max(0.0, min(windowSize, t - windowPosition)) / windowSize;
    return 1.0 - particleEaseInWindowFunction(windowT);
}
float2 grad(float2 z) {
    int n = z.x + z.y * 11111.0;
    n = (n << 13) ^ n;
    n = (n * (n * n * 15731 + 789221) + 1376312589) >> 16;
    n &= 7;
    float2 gr = float2(n & 1, n >> 1) * 2.0 - 1.0;
    return (n >= 6) ? float2(0.0, gr.x) : (n >= 4) ? float2(gr.x, 0.0) : gr;
}
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(grad(i+float2(0,0)), f-float2(0,0)), dot(grad(i+float2(1,0)), f-float2(1,0)), u.x),
               mix(dot(grad(i+float2(0,1)), f-float2(0,1)), dot(grad(i+float2(1,1)), f-float2(1,1)), u.x), u.y);
}
static float dustReleasePosition(uint2 size, uint particleX, uint particleY, uint gid) {
    float2 position = float2(particleX, particleY);
    float shape = clamp(0.5 + 0.6 * (noise(position / 22.0) + 0.5 * noise(position / 9.0 + 31.0)), 0.0, 1.0);
    return 0.5 * float(particleX) / float(size.x) + 0.2 * shape + 0.3 * dustRandom(gid, 6);
}
struct ParticleFluidParams {
    float2 itemOrigin;
    float2 itemSize;
    float cellSize;
    float isEnabled;
};
static float dustStreamFunctionAt(texture2d<float, access::read> streamFunction, int2 position) {
    int2 maxPosition = int2(streamFunction.get_width(), streamFunction.get_height()) - 1;
    if (any(position < 0) || any(position > maxPosition)) return 0.0;
    return streamFunction.read(uint2(position)).x;
}
static float2 dustFlowVelocity(texture2d<float, access::read> streamFunction, float cellSize, float2 position) {
    float2 gridPosition = position / cellSize - 0.5;
    float2 cell = floor(gridPosition);
    float2 fraction = gridPosition - cell;
    int2 origin = int2(cell);
    float s00 = dustStreamFunctionAt(streamFunction, origin);
    float s10 = dustStreamFunctionAt(streamFunction, origin + int2(1, 0));
    float s01 = dustStreamFunctionAt(streamFunction, origin + int2(0, 1));
    float s11 = dustStreamFunctionAt(streamFunction, origin + int2(1, 1));
    float dx = mix(s10 - s00, s11 - s01, fraction.y);
    float dy = mix(s01 - s00, s11 - s10, fraction.x);
    return float2(dy, -dx) * cellSize;
}
kernel void dustEffectUpdateParticle(
    device Particle *particles [[ buffer(0) ]],
    const device uint2 &size [[ buffer(1) ]],
    const device float &phase [[ buffer(2) ]],
    const device float &timeStep [[ buffer(3) ]],
    const device float &verticalDirection [[ buffer(4) ]],
    const device ParticleFluidParams &fluid [[ buffer(5) ]],
    texture2d<float, access::read> streamFunction [[ texture(0) ]],
    uint gid [[ thread_position_in_grid ]]
) {
    if (gid >= size.x * size.y) return;
    constexpr float easeInDuration = 0.8;
    float effectFraction = max(0.0, min(easeInDuration, phase)) / easeInDuration;
    uint particleX = gid % size.x;
    uint particleY = gid / size.x;
    float particleXFraction = dustReleasePosition(size, particleX, particleY, gid);
    float particleFraction = particleEaseInValueAt(effectFraction, particleXFraction);
    constexpr float looseningDistance = 16.0;
    float looseness = 0.0;
    if (particleFraction > 0.0) {
        looseness = 1.0 - smoothstep(0.0, 0.3, particleFraction);
    } else {
        float releaseStart = 1.8 * effectFraction;
        float distanceAhead = (particleXFraction - releaseStart) * float(size.x);
        looseness = pow(max(0.0, 1.0 - distanceAhead / looseningDistance), 2.0);
    }
    if (particleFraction <= 0.0 && looseness <= 0.0) return;
    Particle particle = particles[gid];
    if (particle.lifetime <= 0.0) return;
    float2 flowVelocity = float2(0.0);
    if (fluid.isEnabled != 0.0) {
        float2 basePosition = (float2(particleX, particleY) + 0.5) * fluid.itemSize / float2(size);
        float2 position = fluid.itemOrigin + basePosition + float2(particle.offsetFromBasePosition);
        float stepTime = timeStep * particleFraction;
        float2 startVelocity = dustFlowVelocity(streamFunction, fluid.cellSize, position);
        flowVelocity = dustFlowVelocity(streamFunction, fluid.cellSize, position + startVelocity * (0.5 * stepTime));
        Loki rng = Loki(gid, 7);
        flowVelocity *= 0.85 + rng.rand() * 0.3;
    }
    float2 shiver = float2(sin(phase * 69.0 + dustRandom(gid, 1) * 6.283), sin(phase * 83.0 + dustRandom(gid, 2) * 6.283));
    particle.displacement = packed_float2(looseness * (shiver * 0.4 + flowVelocity * 0.006));
    if (particleFraction <= 0.0) {
        particles[gid] = particle;
        return;
    }
    float2 ownVelocity = float2(particle.velocity);
    ownVelocity += (float2(0.0, 60.0 * verticalDirection) - ownVelocity * 1.5) * timeStep * particleFraction;
    particle.velocity = packed_float2(ownVelocity);
    float hang = mix(1.0, 0.35, 1.0 - smoothstep(1.6, 2.3, particle.lifetime));
    particle.offsetFromBasePosition += ((ownVelocity + flowVelocity) * timeStep) * particleFraction * hang;
    particle.lifetime = max(0.0, particle.lifetime - timeStep * particleFraction);
    particle.age += timeStep * particleFraction;
    particles[gid] = particle;
}
vertex QuadVertexOut dustEffectVertex(
    const device Rectangle &rect [[ buffer(0) ]],
    const device float2 &size [[ buffer(1) ]],
    const device uint2 &particleResolution [[ buffer(2) ]],
    const device Particle *particles [[ buffer(3) ]],
    unsigned int vid [[ vertex_id ]],
    unsigned int particleId [[ instance_id ]]
) {
    QuadVertexOut out;
    float2 quadVertex = quadVertices[vid];
    uint particleIndexX = particleId % particleResolution.x;
    uint particleIndexY = particleId / particleResolution.x;
    Particle particle = particles[particleId];
    float2 particleSize = size / float2(particleResolution);
    float2 topLeftPosition = float2(float(particleIndexX) * particleSize.x, float(particleIndexY) * particleSize.y);
    out.uv = (topLeftPosition + quadVertex * particleSize) / size;
    constexpr float onePixel = 1.0 / 3.0;
    float released = smoothstep(0.0, 0.25, particle.age);
    // Keep the visible grain smaller as particle density increases on device.
    float grainSize = 0.3 + 0.6 * pow(dustRandom(particleId, 3), 2.2);
    float dwindleStart = 0.1 + 0.3 * dustRandom(particleId, 9);
    float dwindleDuration = 0.5 + 0.8 * dustRandom(particleId, 10);
    float dwindleProgress = clamp((particle.age - dwindleStart) / dwindleDuration, 0.0, 1.0);
    float dwindled = 1.0 - (1.0 - dwindleProgress) * (1.0 - dwindleProgress);
    float goingOut = smoothstep(0.0, 0.3, particle.lifetime);
    float grainPoints = mix(grainSize * 1.13, onePixel, dwindled);
    float scale = mix(1.0, grainPoints / particleSize.x, released);
    float intensity = 0.12 + 0.88 * pow(dustRandom(particleId, 7), 4.0);
    float twinkle = particle.age * 12.0 + dustRandom(particleId, 8);
    float flash = dustRandom(particleId, 1000u + uint(twinkle));
    float peak = flash > 0.45 ? 0.6 + 0.4 * flash : 0.15;
    float rise = sin(fract(twinkle) * M_PI_F);
    float flicker = mix(0.15, peak, rise * rise);
    float glint = released * smoothstep(0.85, 1.0, dwindled) * intensity * flicker * goingOut;
    float bloom = glint * smoothstep(0.45, 0.85, glint);
    float quadScale = max(scale, 4.0 * bloom / particleSize.x);
    float2 center = topLeftPosition + 0.5 * particleSize + float2(particle.offsetFromBasePosition) + float2(particle.displacement);
    float2 position = center + (quadVertex - 0.5) * particleSize * quadScale;
    out.position = float4(mapLocalToScreenCoordinates(rect, size, position), 0.0, 1.0);
    out.alpha = particle.lifetime > 0.0 ? goingOut : 0.0;
    out.local = quadVertex * 2.0 - 1.0;
    out.roundness = released * smoothstep(0.5, 1.0, grainPoints);
    out.grainRadius = scale / quadScale;
    out.glint = glint;
    out.bloom = bloom;
    if (out.alpha <= 0.0) out.position = float4(-2.0, -2.0, 0.0, 1.0);
    return out;
}
fragment half4 dustEffectFragment(
    QuadVertexOut in [[stage_in]],
    texture2d<half, access::sample> inTexture [[ texture(0) ]]
) {
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    half4 grainColor = inTexture.sample(sampler, float2(in.uv.x, 1.0 - in.uv.y));
    float mask = 1.0;
    if (in.roundness > 0.0 || in.grainRadius < 1.0) {
        float squareDistance = max(abs(in.local.x), abs(in.local.y));
        float distance = mix(squareDistance, length(in.local), in.roundness);
        mask = saturate((in.grainRadius - distance) / max(fwidth(distance), 0.0001) + 0.5);
    }
    half4 color = grainColor * half(in.alpha * mask);
    if (in.glint > 0.0) {
        half3 tint = mix(grainColor.rgb / max(grainColor.a, 0.001h), half3(1.0h, 0.98h, 0.94h), 0.8h);
        color.rgb = mix(color.rgb, tint * color.a, half(min(1.0, in.glint * 2.0)));
        if (in.bloom > 0.0) {
            half glow = half(exp(-dot(in.local, in.local) * 6.0) * 0.75 * in.bloom * (1.0 - in.grainRadius));
            color += half4(glow * tint, glow * 0.7h) * (1.0h - color.a);
        }
    }
    return color;
}
