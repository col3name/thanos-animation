import Foundation
import UIKit
import MetalKit
import simd

/// Metal implementation of MyTonWallet's hero balance-particle preset.
/// The constants and interpolation curve mirror the production iOS effect.
final class BalanceParticlesMetalView: MTKView, MTKViewDelegate {
    private enum HeroPreset {
        static let travel: CGFloat = 10
        static let destinationMix: CGFloat = 0.2
        static let turbulence: CGFloat = 1
        static let stagger: CGFloat = 0.2
        static let rotation: CGFloat = 40 * .pi / 180
        static let fragmentSize: CGFloat = 1.6
        static let finalParticleSize: Float = 2.2 * 0.7
        static let frequency: CGFloat = 0.75
        static let spread: CGFloat = 24
        static let blendStart: Float = 0.10
        static let blendEnd: Float = 0.75
        static let localDuration: CGFloat = 0.78
    }

    private struct GlyphUniforms {
        var viewport: SIMD2<Float>
        var progress: Float
        var particleSize: Float
        var blend: SIMD4<Float>
    }

    private struct DustUniforms {
        var viewport: SIMD2<Float>
        var opacity: Float
        var padding: Float = 0
    }

    /// Matches `GlyphTile` in BalanceParticles.metal.
    private struct GlyphShard {
        var source: SIMD2<Float>
        var destination: SIMD2<Float>
        var bend: SIMD2<Float>
        var size: SIMD2<Float>
        var textureWindow: SIMD4<Float>
        var timing: SIMD4<Float>
        var cloud: SIMD4<Float>
    }

    private struct DustPoint {
        var position: SIMD2<Float>
        var radius: Float
        var opacity: Float
        var color: SIMD4<Float>
    }

    private struct DustSample {
        var position: CGPoint
        var diameter: CGFloat
        var opacity: CGFloat
    }

    private struct DustSeed {
        var anchor: CGPoint
        var drift: CGPoint
        var phase: CGFloat
        var opacity: CGFloat
        var radius: CGFloat
        var color: SIMD4<Float>
        var isChange: Bool
        var repulsionOffset = CGPoint.zero
        var repulsionVelocity = CGPoint.zero
        var reach: CGFloat
        var strength: CGFloat
        var deflection: CGFloat
        var response: CGFloat
    }

    private let deviceContext: MTLDevice
    private let commands: MTLCommandQueue
    private var dustPipeline: MTLRenderPipelineState?
    private var textPipeline: MTLRenderPipelineState?
    private let textureLoader: MTKTextureLoader
    private var glyphTexture: MTLTexture?
    private var glyphBuffer: MTLBuffer?
    private var glyphs = [GlyphShard]()
    private var glyphCloudIndices = [Int]()
    private var seeds = [DustSeed]()
    private var clock: CGFloat = 0
    private var progress: Float = 0
    var touchLocation: CGPoint?
    private(set) var cloudBounds = CGRect.zero
    private(set) var changeCloudBounds = CGRect.zero

    /// Labeled because `UIView.init()` is non-failable.
    init?(ifAvailable _: Void) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commands = device.makeCommandQueue() else { return nil }
        deviceContext = device
        self.commands = commands
        textureLoader = MTKTextureLoader(device: device)
        super.init(frame: .zero, device: device)

        do {
            let library = try device.makeDefaultLibrary(bundle: .main)
            func makePipeline(vertex: String, fragment: String) throws -> MTLRenderPipelineState {
                let description = MTLRenderPipelineDescriptor()
                description.vertexFunction = library.makeFunction(name: vertex)
                description.fragmentFunction = library.makeFunction(name: fragment)
                let attachment = description.colorAttachments[0]!
                attachment.pixelFormat = .bgra8Unorm
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: description)
            }
            textPipeline = try makePipeline(vertex: "balanceGlyphVertex", fragment: "balanceGlyphFragment")
            dustPipeline = try makePipeline(vertex: "balanceDustVertex", fragment: "balanceDustFragment")
        } catch {
            NSLog("Cannot initialize balance particle shaders: %@", String(describing: error))
            return nil
        }

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        backgroundColor = .clear
        isOpaque = false
        isPaused = true
        enableSetNeedsDisplay = true
        framebufferOnly = true
        preferredFramesPerSecond = 60
        delegate = self
        isHidden = true
        accessibilityElementsHidden = true
    }

    required init(coder: NSCoder) { fatalError("Use init(ifAvailable:)") }

    func setCloudBounds(_ amount: CGRect, change: CGRect) {
        guard amount.width > 0, amount.height > 0, change.width > 0, change.height > 0,
              amount != cloudBounds || change != changeCloudBounds else { return }
        cloudBounds = amount
        changeCloudBounds = change
        var random = RandomSequence(seed: 0xCA4D51DE)
        seeds.removeAll(keepingCapacity: true)
        appendSeeds(in: amount, color: SIMD4(1, 1, 1, 1), isChange: false, random: &random)
        // MyTonWallet's TextLime / positiveBalance color.
        appendSeeds(in: change, color: SIMD4(123.0 / 255.0, 1, 157.0 / 255.0, 1),
                    isChange: true, random: &random)
        setNeedsDisplay()
    }

    private func appendSeeds(in rect: CGRect, color: SIMD4<Float>, isChange: Bool,
                             random: inout RandomSequence) {
        let count = min(6000, max(24, Int(rect.width * rect.height * 0.28 * HeroPreset.frequency)))
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        for _ in 0..<count {
            var point: CGPoint
            repeat {
                point = CGPoint(x: rect.minX + random.unit() * rect.width,
                                y: rect.minY + random.unit() * rect.height)
            } while !path.contains(point)
            let angle = random.unit() * .pi * 2
            let speed = 0.25 + random.unit() * 0.75
            let phase = random.unit()
            func variation(_ salt: CGFloat) -> CGFloat {
                let value = sin(phase * 127.1 + salt) * 43758.5453
                return value - floor(value)
            }
            seeds.append(DustSeed(
                anchor: point,
                drift: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed),
                phase: phase,
                opacity: 0.35 + random.unit() * 0.65,
                radius: (0.35 + random.unit() * 0.35) * 2.2,
                color: color,
                isChange: isChange,
                reach: 0.82 + variation(1.7) * 0.36,
                strength: 0.4 + variation(8.3) * 0.6,
                deflection: (variation(24.9) - 0.5) * 0.65,
                response: 0.8 + variation(63.1) * 0.4
            ))
        }
    }

    func prepareText(_ image: UIImage, displayedIn rect: CGRect, origin: CGPoint) {
        guard let cgImage = image.cgImage, !seeds.isEmpty else { return }
        do {
            glyphTexture = try textureLoader.newTexture(
                cgImage: cgImage,
                options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft]
            )
        } catch {
            NSLog("Texture upload error: %@", String(describing: error))
            glyphTexture = nil
            return
        }

        let width = cgImage.width
        let height = cgImage.height
        let rowBytes = width * 4
        guard let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: rowBytes,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = bitmap.data else { return }
        bitmap.translateBy(x: 0, y: CGFloat(height))
        bitmap.scaleBy(x: 1, y: -1)
        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let rgba = data.assumingMemoryBound(to: UInt8.self)
        var random = RandomSequence(seed: 0xD1571A7E)
        var fragments = [GlyphShard]()
        var indices = [Int]()
        var uses = Array(repeating: 0, count: seeds.count)
        let samples = currentSamples()
        let desired = max(0.8, HeroPreset.fragmentSize / sqrt(HeroPreset.frequency))
        let densityLimit = sqrt(rect.width * rect.height / 9000)
        let pixelScale = CGFloat(width) / max(1, rect.width)
        let step = max(1, Int(ceil(max(desired, densityLimit) * pixelScale)))
        let diagonal = max(1, hypot(rect.width, rect.height))

        for py in stride(from: 0, to: height, by: step) {
            for px in stride(from: 0, to: width, by: step) {
                let tileWidth = min(step, width - px)
                let tileHeight = min(step, height - py)
                var hasInk = false
                scan: for y in py..<(py + tileHeight) {
                    for x in px..<(px + tileWidth) where rgba[y * rowBytes + x * 4 + 3] > 8 {
                        hasInk = true
                        break scan
                    }
                }
                guard hasInk else { continue }

                let u = CGFloat(px) / CGFloat(width)
                let v = CGFloat(py) / CGFloat(height)
                let uw = CGFloat(tileWidth) / CGFloat(width)
                let vh = CGFloat(tileHeight) / CGFloat(height)
                let center = CGPoint(x: rect.minX + (u + uw / 2) * rect.width,
                                     y: rect.minY + (v + vh / 2) * rect.height)
                let isChange = changeCloudBounds.insetBy(dx: -30, dy: -12).contains(center)
                let field = isChange ? changeCloudBounds : cloudBounds

                var randomDestination: CGPoint
                let fieldPath = UIBezierPath(roundedRect: field, cornerRadius: field.height / 2)
                repeat {
                    randomDestination = CGPoint(x: field.minX + random.unit() * field.width,
                                                y: field.minY + random.unit() * field.height)
                } while !fieldPath.contains(randomDestination)
                let local = project(center, into: field)
                var destination = CGPoint(
                    x: local.x + (randomDestination.x - local.x) * HeroPreset.destinationMix,
                    y: local.y + (randomDestination.y - local.y) * HeroPreset.destinationMix
                )

                let candidates = seeds.indices.filter { seeds[$0].isChange == isChange }
                let cloudIndex = candidates.min { lhs, rhs in
                    let lp = samples[lhs].position
                    let rp = samples[rhs].position
                    let left = hypot(lp.x - destination.x, lp.y - destination.y) + CGFloat(uses[lhs]) * 12
                    let right = hypot(rp.x - destination.x, rp.y - destination.y) + CGFloat(uses[rhs]) * 12
                    return left < right
                } ?? -1
                let sample = cloudIndex >= 0 ? samples[cloudIndex] : nil
                if cloudIndex >= 0 {
                    uses[cloudIndex] += 1
                    destination = sample!.position
                }

                let dx = center.x - origin.x
                let dy = center.y - origin.y
                let distance = max(1, hypot(dx, dy))
                let travel = HeroPreset.travel * (1 + (random.unit() * 2 - 1) * HeroPreset.turbulence)
                let delay = min(1, distance / diagonal) * HeroPreset.stagger

                fragments.append(GlyphShard(
                    source: SIMD2(Float(center.x), Float(center.y)),
                    destination: SIMD2(Float(destination.x), Float(destination.y)),
                    bend: SIMD2(Float(dx / distance * travel), Float(dy / distance * travel)),
                    size: SIMD2(Float(uw * rect.width), Float(vh * rect.height)),
                    textureWindow: SIMD4(Float(u), Float(v), Float(uw), Float(vh)),
                    timing: SIMD4(Float(delay), Float(0.6 + random.unit() * 0.8),
                                  Float((random.unit() * 2 - 1) * HeroPreset.rotation),
                                  Float(HeroPreset.localDuration)),
                    cloud: SIMD4(0, 0, Float(sample?.diameter ?? 0), Float(sample?.opacity ?? -1))
                ))
                indices.append(cloudIndex)
            }
        }

        glyphs = fragments
        glyphCloudIndices = indices
        let length = fragments.count * MemoryLayout<GlyphShard>.stride
        glyphBuffer = length > 0 ? deviceContext.makeBuffer(length: length, options: .storageModeShared) : nil
        uploadGlyphs()
    }

    private func project(_ point: CGPoint, into field: CGRect) -> CGPoint {
        var result = CGPoint(x: min(field.maxX, max(field.minX, point.x)),
                             y: min(field.maxY, max(field.minY, point.y)))
        let shape = UIBezierPath(roundedRect: field, cornerRadius: field.height / 2)
        guard !shape.contains(result) else { return result }
        let radius = field.height / 2
        let centerX = min(field.maxX - radius, max(field.minX + radius, result.x))
        let dx = result.x - centerX
        let dy = result.y - field.midY
        let scale = (radius - 0.01) / max(radius, hypot(dx, dy))
        result = CGPoint(x: centerX + dx * scale, y: field.midY + dy * scale)
        return result
    }

    func releaseTextTexture() {
        glyphTexture = nil
        glyphBuffer = nil
        glyphs.removeAll(keepingCapacity: true)
        glyphCloudIndices.removeAll(keepingCapacity: true)
    }

    func advance(delta: CGFloat) {
        let dt = min(max(delta, 0), 1.0 / 15.0)
        clock += dt
        for index in seeds.indices {
            var seed = seeds[index]
            let resting = restingPosition(of: seed)
            var target = CGPoint.zero
            if let finger = touchLocation {
                let dx = resting.x - finger.x
                let dy = resting.y - finger.y
                let distance = hypot(dx, dy)
                let radius = 64 * seed.reach
                if distance < radius {
                    let direction = distance > 0.001 ? CGPoint(x: dx, y: dy) : seed.drift
                    let length = max(0.001, hypot(direction.x, direction.y))
                    let fraction = distance / radius
                    let falloff = 1 - fraction * fraction * (3 - 2 * fraction)
                    let travel = 40 * seed.strength * falloff
                    target = CGPoint(
                        x: (direction.x - direction.y * seed.deflection) / length * travel,
                        y: (direction.y + direction.x * seed.deflection) / length * travel
                    )
                }
            }
            if target != .zero || seed.repulsionOffset != .zero || seed.repulsionVelocity != .zero {
                let rate: CGFloat = (target == .zero ? 14 : 24) * seed.response
                let decay = exp(-rate * dt)
                func step(_ position: CGFloat, _ speed: CGFloat, _ destination: CGFloat) -> (CGFloat, CGFloat) {
                    let delta = position - destination
                    let impulse = speed + rate * delta
                    return (destination + (delta + impulse * dt) * decay,
                            (speed - rate * impulse * dt) * decay)
                }
                (seed.repulsionOffset.x, seed.repulsionVelocity.x) = step(
                    seed.repulsionOffset.x, seed.repulsionVelocity.x, target.x)
                (seed.repulsionOffset.y, seed.repulsionVelocity.y) = step(
                    seed.repulsionOffset.y, seed.repulsionVelocity.y, target.y)
                if target == .zero, hypot(seed.repulsionOffset.x, seed.repulsionOffset.y) < 0.001,
                   hypot(seed.repulsionVelocity.x, seed.repulsionVelocity.y) < 0.005 {
                    seed.repulsionOffset = .zero
                    seed.repulsionVelocity = .zero
                }
            }
            seeds[index] = seed
        }
        setNeedsDisplay()
    }

    func setMorph(_ value: Float) {
        progress = min(1, max(0, value))
        setNeedsDisplay()
    }

    private func restingPosition(of seed: DustSeed) -> CGPoint {
        let age = (clock + seed.phase).truncatingRemainder(dividingBy: 1)
        let travel = (age - 0.5) * 2 * HeroPreset.spread
        return CGPoint(x: seed.anchor.x + seed.drift.x * travel,
                       y: seed.anchor.y + seed.drift.y * travel)
    }

    private func currentSamples() -> [DustSample] {
        seeds.map { seed in
            let age = (clock + seed.phase).truncatingRemainder(dividingBy: 1)
            let envelope = sin(.pi * age)
            let rawOpacity = seed.opacity * envelope * envelope
            let opacity: CGFloat = rawOpacity > 0.005
                ? CGFloat(min(63, max(0, Int(rawOpacity * 64))) + 1) / 64
                : 0
            let point = restingPosition(of: seed)
            return DustSample(
                position: CGPoint(x: point.x + seed.repulsionOffset.x,
                                  y: point.y + seed.repulsionOffset.y),
                diameter: seed.radius * 2,
                opacity: opacity
            )
        }
    }

    private func updateGlyphTargets(from samples: [DustSample]) {
        guard glyphs.count == glyphCloudIndices.count else { return }
        for index in glyphs.indices {
            let cloudIndex = glyphCloudIndices[index]
            guard cloudIndex >= 0, cloudIndex < samples.count else { continue }
            let sample = samples[cloudIndex]
            glyphs[index].destination = SIMD2(Float(sample.position.x), Float(sample.position.y))
            glyphs[index].cloud.z = Float(sample.diameter)
            glyphs[index].cloud.w = Float(sample.opacity)
        }
        uploadGlyphs()
    }

    private func uploadGlyphs() {
        guard let glyphBuffer, !glyphs.isEmpty else { return }
        glyphs.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { return }
            glyphBuffer.contents().copyMemory(from: source, byteCount: bytes.count)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        guard bounds.width > 0, bounds.height > 0,
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let command = commands.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }

        let samples = currentSamples()
        updateGlyphTargets(from: samples)
        let blendPosition = min(1, max(0, (progress - HeroPreset.blendStart)
            / (HeroPreset.blendEnd - HeroPreset.blendStart)))
        let dustOpacity = blendPosition * blendPosition * blendPosition
            * (blendPosition * (blendPosition * 6 - 15) + 10)

        if let glyphTexture, let glyphBuffer, let textPipeline, !glyphs.isEmpty, progress < 1 {
            var uniforms = GlyphUniforms(
                viewport: SIMD2(Float(bounds.width), Float(bounds.height)),
                progress: progress,
                particleSize: HeroPreset.finalParticleSize,
                blend: SIMD4(HeroPreset.blendStart, HeroPreset.blendEnd, 1, 0)
            )
            encoder.setRenderPipelineState(textPipeline)
            encoder.setVertexBuffer(glyphBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<GlyphUniforms>.stride, index: 1)
            encoder.setFragmentTexture(glyphTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                   instanceCount: glyphs.count)
        }

        if dustOpacity > 0.0001, let dustPipeline, !seeds.isEmpty {
            let points = zip(seeds, samples).map { seed, sample in
                DustPoint(position: SIMD2(Float(sample.position.x), Float(sample.position.y)),
                          radius: Float(sample.diameter / 2),
                          opacity: Float(sample.opacity), color: seed.color)
            }
            if let pointBuffer = points.withUnsafeBytes({ bytes -> MTLBuffer? in
                guard let pointer = bytes.baseAddress, !bytes.isEmpty else { return nil }
                return deviceContext.makeBuffer(bytes: pointer, length: bytes.count, options: .storageModeShared)
            }) {
                var uniforms = DustUniforms(
                    viewport: SIMD2(Float(bounds.width), Float(bounds.height)),
                    opacity: dustOpacity
                )
                encoder.setRenderPipelineState(dustPipeline)
                encoder.setVertexBuffer(pointBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<DustUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                       instanceCount: points.count)
            }
        }
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}

private struct RandomSequence {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 32) / CGFloat(UInt32.max)
    }
}
