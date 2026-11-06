import UIKit
import Metal
import MetalKit
import QuartzCore

/// Standalone MTKView adapter around Telegram's DustEffect particle / fluid shader algorithms.
/// Accepts a screenshot of a UIKit chat row and renders the disintegration independently
/// of the table's reuse, scroll and delete animations.
final class DustEffectView: UIView, MTKViewDelegate {
    private final class Item {
        let frame: CGRect
        let texture: MTLTexture
        let buffer: MTLBuffer
        let count: Int
        let resolution: SIMD2<UInt32>
        var phase: Float = 0
        var elapsed: Float = 0
        var initialized = false
        var readyForRendering = false

        init?(frame: CGRect, image: UIImage, device: MTLDevice) {
            guard let cgImage = image.cgImage,
                  let texture = try? MTKTextureLoader(device: device).newTexture(
                    cgImage: cgImage, options: [.SRGB: false as NSNumber]) else { return nil }
            // Use a 2× finer grid in each direction: four times as many
            // particles, each covering half the width and height of the old cell.
            let particleDensity: CGFloat = 2
            let columns = max(1, Int((frame.width * particleDensity).rounded(.down)))
            let rows = max(1, Int((frame.height * particleDensity).rounded(.down)))
            let count = columns * rows
            // The Metal Particle struct is 8 floats = 32 bytes (including packed_float2 fields).
            guard let buffer = device.makeBuffer(length: count * 32, options: .storageModePrivate) else { return nil }
            self.frame = frame
            self.texture = texture
            self.buffer = buffer
            self.count = count
            self.resolution = SIMD2<UInt32>(UInt32(columns), UInt32(rows))
        }
    }

    private struct ParticleFluidParams {
        var itemOrigin: SIMD2<Float>
        var itemSize: SIMD2<Float>
        var cellSize: Float
        var isEnabled: Float
    }

    private let device: MTLDevice?
    private var metalView: MTKView?
    private var commandQueue: MTLCommandQueue?
    private var drawPipeline: MTLRenderPipelineState?
    private var initializePipeline: MTLComputePipelineState?
    private var updatePipeline: MTLComputePipelineState?
    private var items: [Item] = []
    private var previousFrameTime: CFTimeInterval?
    private var lastTimeStep: Float = 0

    var animationSpeed: Float = 1
    var animateDown: Bool = false
    var onUnavailable: (() -> Void)?

    override init(frame: CGRect) {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        guard let device else {
            NSLog("Telegram DustEffect initialization failed: no system Metal device.")
            return
        }
        guard let queue = device.makeCommandQueue() else {
            NSLog("Telegram DustEffect initialization failed: could not create a Metal command queue.")
            return
        }
        // Explicitly query the app bundle on device, then fall back to the default
        // library lookup used by Xcode's generated metallib.
        let library = (try? device.makeDefaultLibrary(bundle: .main)) ?? device.makeDefaultLibrary()
        guard let library else {
            NSLog("Telegram DustEffect initialization failed: default.metallib is missing from the app bundle.")
            return
        }
        guard let vertex = library.makeFunction(name: "dustEffectVertex"),
              let fragment = library.makeFunction(name: "dustEffectFragment"),
              let initialize = library.makeFunction(name: "dustEffectInitializeParticle"),
              let update = library.makeFunction(name: "dustEffectUpdateParticle") else {
            NSLog("Telegram DustEffect initialization failed: required particle kernels are missing from default.metallib.")
            return
        }
        guard let initPipeline = try? device.makeComputePipelineState(function: initialize),
              let updatePipeline = try? device.makeComputePipelineState(function: update) else {
            NSLog("Telegram DustEffect initialization failed: could not compile the particle compute pipelines.")
            return
        }

        let mtk = MTKView(frame: bounds, device: device)
        mtk.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtk.backgroundColor = .clear
        mtk.isOpaque = false
        mtk.clearColor = MTLClearColorMake(0, 0, 0, 0)
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.framebufferOnly = true
        mtk.preferredFramesPerSecond = 60
        mtk.enableSetNeedsDisplay = false
        mtk.isPaused = true
        mtk.delegate = self
        addSubview(mtk)

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let drawPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            NSLog("Telegram DustEffect initialization failed: could not compile the particle render pipeline.")
            return
        }
        self.metalView = mtk
        self.commandQueue = queue
        self.drawPipeline = drawPipeline
        self.initializePipeline = initPipeline
        self.updatePipeline = updatePipeline
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // MTKView is created while the overlay still has a zero-sized frame.
        // Set its frame explicitly after Auto Layout assigns the final bounds.
        metalView?.frame = bounds
    }

    var isReady: Bool {
        metalView != nil && drawPipeline != nil && initializePipeline != nil && updatePipeline != nil
    }

    /// The `frame` must be in this view's point coordinate system; the `image` is
    /// a pixel-accurate snapshot of that same rectangle.
    @discardableResult
    func dissolve(image: UIImage, at frame: CGRect) -> Bool {
        guard let device, isReady, !frame.isEmpty else {
            NSLog("Telegram DustEffect could not start: renderer ready=%@, frame=%@.", String(isReady), String(describing: frame))
            onUnavailable?()
            return false
        }
        guard let item = Item(frame: frame, image: image, device: device) else {
            NSLog("Telegram DustEffect could not start: could not upload the chat snapshot as a Metal texture.")
            onUnavailable?()
            return false
        }
        if items.isEmpty {
            previousFrameTime = nil
        }
        items.append(item)
        isHidden = false
        metalView?.isPaused = false
        return true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let queue = commandQueue,
              let initPipeline = initializePipeline,
              let updatePipeline = updatePipeline,
              let drawPipeline = drawPipeline,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer() else { return }

        if items.isEmpty {
            view.isPaused = true
            isHidden = true
            return
        }

        let timestamp = CACurrentMediaTime()
        let elapsed = previousFrameTime.map { timestamp - $0 } ?? 1.0 / 60.0
        previousFrameTime = timestamp
        // Avoid huge physics steps after an incoming call, app suspension or debugger pause.
        let dt = Float(max(1.0 / 120.0, min(elapsed, 1.0 / 30.0)))
        lastTimeStep = dt
        let vertical: Float = animateDown ? -1 : 1
        for item in items {
            item.phase += dt * animationSpeed
            item.elapsed += dt
        }

        var initializedThisFrame = Set<ObjectIdentifier>()
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            for item in items {
                var direction = vertical
                var resolution = item.resolution
                let groups = MTLSize(width: (item.count + 31) / 32, height: 1, depth: 1)
                let threads = MTLSize(width: 32, height: 1, depth: 1)
                encoder.setBuffer(item.buffer, offset: 0, index: 0)
                if !item.initialized {
                    item.initialized = true
                    encoder.setComputePipelineState(initPipeline)
                    encoder.setBytes(&direction, length: MemoryLayout<Float>.size, index: 1)
                    encoder.setBytes(&resolution, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 2)
                    encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
                    // Keep initialization and update in separate GPU frames. This avoids
                    // a same-encoder read-after-write hazard on physical iPhone GPUs.
                    initializedThisFrame.insert(ObjectIdentifier(item))
                    continue
                }
                encoder.setComputePipelineState(updatePipeline)
                encoder.setBytes(&resolution, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
                var phase = item.phase
                var step = dt * 2
                encoder.setBytes(&phase, length: MemoryLayout<Float>.size, index: 2)
                encoder.setBytes(&step, length: MemoryLayout<Float>.size, index: 3)
                encoder.setBytes(&direction, length: MemoryLayout<Float>.size, index: 4)
                var params = ParticleFluidParams(
                    itemOrigin: SIMD2<Float>(Float(item.frame.minX), Float(bounds.height - item.frame.maxY)),
                    itemSize: SIMD2<Float>(Float(item.frame.width), Float(item.frame.height)),
                    cellSize: 1,
                    isEnabled: 0
                )
                encoder.setBytes(&params, length: MemoryLayout<ParticleFluidParams>.stride, index: 5)
                encoder.setTexture(item.texture, index: 0)
                encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
                item.readyForRendering = true
            }
            encoder.endEncoding()
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(drawPipeline)
            for item in items {
                guard item.readyForRendering,
                      !initializedThisFrame.contains(ObjectIdentifier(item)) else { continue }
                let f = item.frame
                // Original shader works in bottom-left-origin normalized coordinates.
                var rect = SIMD4<Float>(
                    Float(f.minX / bounds.width),
                    Float((bounds.height - f.maxY) / bounds.height),
                    Float(f.width / bounds.width),
                    Float(f.height / bounds.height)
                )
                var size = SIMD2<Float>(Float(f.width), Float(f.height))
                var resolution = item.resolution
                encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
                encoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 2)
                encoder.setVertexBuffer(item.buffer, offset: 0, index: 3)
                encoder.setFragmentTexture(item.texture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: item.count)
            }
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        items.removeAll(where: { $0.phase >= 4 && $0.elapsed >= 2.9 })
        if items.isEmpty {
            // Keep the last GPU render from being visible once the overlay is idle.
            view.isPaused = true
            isHidden = true
            previousFrameTime = nil
        }
    }
}
