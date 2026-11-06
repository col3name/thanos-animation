import UIKit
import MetalKit

/// A self-contained, interactive balance view. No wallet code or third-party modules.
final class PrivacyBalanceView: UIView, UIGestureRecognizerDelegate {
    var onStateChanged: ((Bool) -> Void)?

    private enum Phase { case visible, disappearing, concealed, appearing }
    private var phase: Phase = .visible
    private let amountLabel = UILabel()
    private let changeBackground = UIView()
    private let changeLabel = UILabel()
    // Keep the renderer optional: the view has a non-animated fallback when
    // Metal or the app's shader library is unavailable.
    private let metal = BalanceParticlesMetalView(ifAvailable: ())
    private var displayLink: CADisplayLink?
    private var priorTick: CFTimeInterval = 0
    private var morph: CGFloat = 0
    private let concealSeconds: CGFloat = 0.70
    private let revealSeconds: CGFloat = 0.60
    private let blendEnd: CGFloat = 0.75
    private var lastTextLayout = CGRect.zero
    private var previousSize = CGSize.zero
    private var transitionOrigin: CGPoint?
    private let amount = "$12,483.31"
    private let dailyChange = "↗  +2.84%  ·  сегодня"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        amountLabel.text = amount
        let sourceFont = UIFont.systemFont(ofSize: 43, weight: .semibold)
        amountLabel.font = UIFont(descriptor: sourceFont.fontDescriptor.withDesign(.rounded) ?? sourceFont.fontDescriptor, size: 43)
        amountLabel.textColor = .white
        amountLabel.textAlignment = .center
        amountLabel.adjustsFontSizeToFitWidth = false
        amountLabel.isUserInteractionEnabled = false
        amountLabel.accessibilityElementsHidden = true

        let positiveBalance = UIColor(red: 123 / 255, green: 1, blue: 157 / 255, alpha: 1)
        changeBackground.backgroundColor = positiveBalance.withAlphaComponent(0.16)
        changeBackground.layer.cornerRadius = 12
        changeBackground.layer.cornerCurve = .continuous
        changeBackground.isUserInteractionEnabled = false

        changeLabel.text = dailyChange
        changeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        changeLabel.textColor = positiveBalance
        changeLabel.textAlignment = .center
        changeLabel.isUserInteractionEnabled = false
        changeLabel.accessibilityElementsHidden = true

        addSubview(changeBackground)
        if let metal {
            metal.isUserInteractionEnabled = false
            addSubview(metal)
        }
        addSubview(amountLabel)
        addSubview(changeLabel)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        drag.delegate = self
        drag.maximumNumberOfTouches = 1
        drag.cancelsTouchesInView = false
        addGestureRecognizer(drag)
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        refreshAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        metal?.frame = bounds
        let recommendedFontSize = min(43, max(28, (bounds.width - 15) / 6.8))
        if abs(amountLabel.font.pointSize - recommendedFontSize) > 0.1 {
            let font = UIFont.systemFont(ofSize: recommendedFontSize, weight: .semibold)
            amountLabel.font = UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor,
                                      size: recommendedFontSize)
        }
        let sized = amountLabel.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let w = min(bounds.width, ceil(sized.width + 3))
        let h = min(68, ceil(sized.height + 4))
        amountLabel.frame = CGRect(x: (bounds.width - w) / 2, y: 0,
                                   width: w, height: h)
        changeBackground.frame = CGRect(x: (bounds.width - 184) / 2,
                                        y: min(bounds.height - 27, 72),
                                        width: 184, height: 27)
        changeLabel.frame = changeBackground.frame
        // Production home-card field: 14 columns × 16 pt sensitive-data cell.
        let cloudWidth = min(bounds.width, 224)
        let center = CGPoint(x: bounds.midX, y: amountLabel.frame.midY)
        let cloudRect = CGRect(x: center.x - cloudWidth / 2, y: center.y - 17,
                               width: cloudWidth, height: 34)
        let changeCloudRect = CGRect(x: bounds.midX - 65, y: changeLabel.frame.midY - 13.5,
                                     width: 130, height: 27)
        if let metal, previousSize != bounds.size || cloudRect != metal.cloudBounds
            || changeCloudRect != metal.changeCloudBounds {
            metal.setCloudBounds(cloudRect, change: changeCloudRect)
            previousSize = bounds.size
        }
        let textLayout = amountLabel.frame.union(changeLabel.frame)
        if textLayout != lastTextLayout {
            lastTextLayout = textLayout
            // Only the current animation needs the temporary glyph texture.
            if phase == .disappearing || phase == .appearing {
                loadGlyphs()
            }
        }
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            transitionOrigin = recognizer.location(in: self)
            toggle()
        }
    }

    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        let wherePressed = recognizer.location(in: self)
        switch recognizer.state {
        case .began, .changed:
            metal?.touchLocation = wherePressed
        default:
            metal?.touchLocation = nil
        }
    }

    func toggle() {
        let goingToHide = (phase == .visible || phase == .appearing)
        if UIAccessibility.isReduceMotionEnabled || metal == nil {
            phase = goingToHide ? .concealed : .visible
            morph = goingToHide ? 1 : 0
            amountLabel.isHidden = goingToHide
            changeLabel.isHidden = goingToHide
            changeBackground.isHidden = goingToHide
            setTransitionTextAlpha(1)
            metal?.setMorph(Float(morph))
            metal?.releaseTextTexture()
            metal?.isHidden = !goingToHide
            // Reduce Motion produces a static cloud, not a continuously moving one.
            stopDisplayLink()
            reportState()
            return
        }
        if phase == .visible || phase == .concealed {
            loadGlyphs()
        }
        if goingToHide {
            phase = .disappearing
            // The Metal glyphs already start at the exact text position, so
            // hiding the UIKit labels here does not create a visible jump.
            setTransitionTextAlpha(1)
        } else {
            phase = .appearing
            // The original reveal starts at the end of the cloud hand-off,
            // avoiding an idle all-dust tail before glyphs reappear.
            morph = min(morph, blendEnd)
            // Keep the labels hidden initially. They fade in only after the
            // particles have almost reached their final text positions.
            setTransitionTextAlpha(0)
        }
        metal?.isHidden = false
        // Draw before hiding the live label, avoiding a one-frame blank.
        metal?.setMorph(Float(morph))
        metal?.draw()
        amountLabel.isHidden = true
        changeLabel.isHidden = true
        changeBackground.isHidden = true
        transitionOrigin = nil
        reportState()
        beginDisplayLink()
    }

    private func loadGlyphs() {
        guard let metal, amountLabel.bounds.width > 0, changeLabel.bounds.width > 0 else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(UIScreen.main.scale, 2)
        format.opaque = false
        // Create an offscreen rendering. We never unhide a concealed UILabel.
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            changeBackground.backgroundColor?.setFill()
            UIBezierPath(roundedRect: changeBackground.frame, cornerRadius: 12).fill()
            drawText(from: amountLabel, in: amountLabel.frame)
            drawText(from: changeLabel, in: changeLabel.frame)
        }
        metal.prepareText(image, displayedIn: bounds,
                          origin: transitionOrigin ?? CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private func drawText(from source: UILabel, in rect: CGRect) {
        guard let value = source.text, let font = source.font, let color = source.textColor else { return }
        let text = NSAttributedString(string: value, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: rect.midX - size.width / 2,
                              y: rect.midY - size.height / 2))
    }

    private func beginDisplayLink() {
        guard displayLink == nil else { return }
        priorTick = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        priorTick = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let delta = priorTick == 0 ? 1.0 / 60.0 : min(0.045, max(0, link.timestamp - priorTick))
        priorTick = link.timestamp
        switch phase {
        case .disappearing:
            morph = min(1, morph + CGFloat(delta) / concealSeconds)
            if morph >= 1 { phase = .concealed; metal?.releaseTextTexture() }
        case .appearing:
            morph = max(0, morph - CGFloat(delta) / revealSeconds * blendEnd)
            // Cross-fade during the last part of the assembly. This avoids a
            // hard switch from the Metal glyphs to UILabels at completion.
            let revealProgress = 1 - min(1, morph / blendEnd)
            let textProgress = smoothStep((revealProgress - 0.62) / 0.38)
            setTransitionTextAlpha(textProgress)
            if textProgress > 0 {
                amountLabel.isHidden = false
                changeLabel.isHidden = false
                changeBackground.isHidden = false
            }
            if morph <= 0 {
                phase = .visible
                amountLabel.isHidden = false
                changeLabel.isHidden = false
                changeBackground.isHidden = false
                setTransitionTextAlpha(1)
                metal?.releaseTextTexture()
                metal?.isHidden = true
                stopDisplayLink()
            }
        case .visible:
            stopDisplayLink()
        case .concealed:
            break
        }
        metal?.advance(delta: CGFloat(delta))
        metal?.setMorph(Float(morph))
    }

    private func refreshAccessibility() {
        accessibilityLabel = phase == .concealed || phase == .disappearing
            ? "Баланс скрыт. Нажмите дважды, чтобы показать."
            : "Баланс \(amount). Нажмите дважды, чтобы скрыть."
    }

    private func setTransitionTextAlpha(_ value: CGFloat) {
        let alpha = min(1, max(0, value))
        amountLabel.alpha = alpha
        changeLabel.alpha = alpha
        changeBackground.alpha = alpha
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func reportState() {
        refreshAccessibility()
        onStateChanged?(phase == .concealed || phase == .disappearing)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopDisplayLink() }
        else if phase != .visible && !UIAccessibility.isReduceMotionEnabled { beginDisplayLink() }
    }
}
