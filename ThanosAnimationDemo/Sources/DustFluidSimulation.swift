// Port of Telegram-iOS DustFluidSimulation.swift to an independent Metal demo.
// Based on https://github.com/TelegramMessenger/Telegram-iOS/tree/master/submodules/TelegramUI/Components/DustEffect
import Foundation
import Metal

final class DustFluidSimulation {
    struct Splat {
        var position: SIMD2<Float>
        var force: SIMD2<Float>
        var radius: Float
        var padding: Float = 0
    }

    struct Pipelines {
        let clear: MTLComputePipelineState
        let splat: MTLComputePipelineState
        let curl: MTLComputePipelineState
        let divergence: MTLComputePipelineState
        let pressure: MTLComputePipelineState
        let gradientSubtract: MTLComputePipelineState
        let advect: MTLComputePipelineState
        let streamFunction: MTLComputePipelineState

        init?(device: MTLDevice, library: MTLLibrary) {
            func make(_ name: String) -> MTLComputePipelineState? {
                guard let fn = library.makeFunction(name: name) else { return nil }
                return try? device.makeComputePipelineState(function: fn)
            }
            guard let clear = make("dustFluidClear"),
                  let splat = make("dustFluidSplat"),
                  let curl = make("dustFluidCurl"),
                  let divergence = make("dustFluidDivergence"),
                  let pressure = make("dustFluidPressure"),
                  let gradientSubtract = make("dustFluidGradientSubtract"),
                  let advect = make("dustFluidAdvect"),
                  let streamFunction = make("dustFluidStreamFunction") else { return nil }
            self.clear = clear
            self.splat = splat
            self.curl = curl
            self.divergence = divergence
            self.pressure = pressure
            self.gradientSubtract = gradientSubtract
            self.advect = advect
            self.streamFunction = streamFunction
        }
    }

    private struct Params {
        var timeStep: Float
        var velocityDissipation: Float
        var pressureScale: Float
    }

    private static let preferredCellSize: Float = 3
    private static let maxGridDimension: Float = 256
    private static let maxSplatCount = 128
    private static let velocityDissipation: Float = 0.2
    private static let pressureDecay: Float = 0.8
    private static let pressureIterations = 20
    private static let maxStep: Float = 1 / 60
    private static let streamFunctionIterations = 30

    let size: SIMD2<Float>
    let cellSize: Float
    let gridWidth: Int
    let gridHeight: Int
    private var velocity: [MTLTexture]
    private var pressure: [MTLTexture]
    private let divergence: MTLTexture
    private let curl: MTLTexture
    private var streamFunction: [MTLTexture]
    private var isCleared = false

    var streamFunctionTexture: MTLTexture { streamFunction[0] }

    init?(device: MTLDevice, size: SIMD2<Float>) {
        guard size.x > 0, size.y > 0 else { return nil }
        let cell = max(Self.preferredCellSize, max(size.x, size.y) / Self.maxGridDimension)
        let width = max(1, Int(ceil(size.x / cell)))
        let height = max(1, Int(ceil(size.y / cell)))
        func make(_ format: MTLPixelFormat, _ label: String) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            desc.storageMode = .private
            desc.usage = [.shaderRead, .shaderWrite]
            let texture = device.makeTexture(descriptor: desc)
            texture?.label = label
            return texture
        }
        guard let v0 = make(.rg16Float, "Dust.velocity0"),
              let v1 = make(.rg16Float, "Dust.velocity1"),
              let p0 = make(.r16Float, "Dust.pressure0"),
              let p1 = make(.r16Float, "Dust.pressure1"),
              let d = make(.r16Float, "Dust.divergence"),
              let c = make(.r16Float, "Dust.curl"),
              let f0 = make(.r32Float, "Dust.flow0"),
              let f1 = make(.r32Float, "Dust.flow1") else { return nil }
        self.size = size
        self.cellSize = cell
        self.gridWidth = width
        self.gridHeight = height
        self.velocity = [v0, v1]
        self.pressure = [p0, p1]
        self.divergence = d
        self.curl = c
        self.streamFunction = [f0, f1]
    }

    func encode(encoder: MTLComputeCommandEncoder, pipelines: Pipelines, timeStep: Float, splats: [Splat]) {
        let groupSize = MTLSize(width: 8, height: 8, depth: 1)
        let groupCount = MTLSize(width: (gridWidth + 7) / 8, height: (gridHeight + 7) / 8, depth: 1)

        func dispatch(_ pipeline: MTLComputePipelineState, _ textures: [MTLTexture]) {
            encoder.setComputePipelineState(pipeline)
            for (i, texture) in textures.enumerated() { encoder.setTexture(texture, index: i) }
            encoder.dispatchThreadgroups(groupCount, threadsPerThreadgroup: groupSize)
        }
        if !isCleared {
            isCleared = true
            for texture in velocity + pressure + streamFunction + [divergence, curl] {
                dispatch(pipelines.clear, [texture])
            }
        }
        if !splats.isEmpty {
            var gridSplats = splats.suffix(Self.maxSplatCount).map {
                Splat(position: $0.position / cellSize, force: $0.force / cellSize, radius: $0.radius / cellSize)
            }
            var count = UInt32(gridSplats.count)
            gridSplats.withUnsafeMutableBufferPointer { buffer in
                if let baseAddress = buffer.baseAddress {
                    encoder.setBytes(baseAddress, length: MemoryLayout<Splat>.stride * buffer.count, index: 0)
                }
            }
            encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 1)
            dispatch(pipelines.splat, [velocity[0], velocity[1]])
            velocity.swapAt(0, 1)
        }
        guard timeStep > 0 else { return }
        let steps = max(1, min(4, Int(ceil(timeStep / Self.maxStep))))
        var params = Params(timeStep: timeStep / Float(steps), velocityDissipation: Self.velocityDissipation, pressureScale: Self.pressureDecay)
        for _ in 0..<steps {
            dispatch(pipelines.divergence, [velocity[0], divergence])
            for i in 0..<Self.pressureIterations {
                params.pressureScale = i == 0 ? Self.pressureDecay : 1
                encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
                dispatch(pipelines.pressure, [pressure[0], divergence, pressure[1]])
                pressure.swapAt(0, 1)
            }
            dispatch(pipelines.gradientSubtract, [pressure[0], velocity[0], velocity[1]])
            velocity.swapAt(0, 1)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            dispatch(pipelines.advect, [velocity[0], velocity[1]])
            velocity.swapAt(0, 1)
        }
        dispatch(pipelines.curl, [velocity[0], curl])
        for _ in 0..<Self.streamFunctionIterations {
            dispatch(pipelines.streamFunction, [streamFunction[0], curl, streamFunction[1]])
            streamFunction.swapAt(0, 1)
        }
    }

    private static let sweepDuration: Float = 0.8
    private static let releaseWindow: Float = 0.8
    private static let areaPerSplat: Float = 700
    private static let initialSplatCount = 3

    static func dissolveSplats<G: RandomNumberGenerator>(origin: SIMD2<Float>, size: SIMD2<Float>, previousPhase: Float, phase: Float, verticalDirection: Float, generator: inout G) -> [Splat] {
        let old = max(0, min(1, previousPhase / sweepDuration))
        let now = max(0, min(1, phase / sweepDuration))
        if now <= old && previousPhase > 0 { return [] }
        var result: [Splat] = []
        func makeSplat(xFraction: Float, magnitude: ClosedRange<Float>, spread: Float) -> Splat {
            let position = origin + SIMD2<Float>(xFraction * size.x, Float.random(in: 0...1, using: &generator) * size.y)
            let angle = Float.pi * 0.5 + Float.random(in: -spread...spread, using: &generator)
            let force = SIMD2<Float>(cos(angle), sin(angle) * verticalDirection) * Float.random(in: magnitude, using: &generator)
            return Splat(position: position, force: force, radius: Float.random(in: 10...18, using: &generator))
        }
        if previousPhase <= 0 {
            for _ in 0..<initialSplatCount {
                result.append(makeSplat(xFraction: Float.random(in: 0...1, using: &generator), magnitude: 9...22, spread: .pi))
            }
        }
        let totalCount = max(4, size.x * size.y / areaPerSplat)
        let count = Int(totalCount * now) - Int(totalCount * old)
        if count > 0 {
            let windowPosition = -releaseWindow + (1 + releaseWindow) * now
            let lo = max(0, windowPosition)
            let hi = min(1, windowPosition + releaseWindow)
            for _ in 0..<count {
                let xFraction = lo < hi ? Float.random(in: lo...hi, using: &generator) : lo
                result.append(makeSplat(xFraction: xFraction, magnitude: 22...56, spread: Float.pi * 0.3))
            }
        }
        return result
    }
}
