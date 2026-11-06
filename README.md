# Balance Privacy — iOS demo

**Standalone UIKit + Metal sample project** demonstrating a wallet balance that dissolves into an animated, interactive cloud of dots and reforms when tapped again.

The particle motion is calibrated against the reference hero-card effect: the same 0.70 s hide phase, 0.60 s reveal phase, 24 pt cloud spread, 10 pt travel, 40° rotation, 0.75 cloud frequency and quintic hand-off are used. The demo remains self-contained and does not include upstream app code or assets.

## Launch

1. Open `BalancePrivacyDemo.xcodeproj` in Xcode 16 or later (Xcode 26.2 is suitable).
2. Select an **iPhone simulator** with iOS 16+ and press **Run (⌘R)**.
3. Tap the large number or **«Скрыть баланс»** to dissolve it into particles.
4. Drag a finger over the hidden amount to scatter the dots. Tap again to restore the amount.
5. During an animation, tap again to reverse it, without starting over.

No Apple Developer membership or provisioning profile is required for an iOS Simulator build. For an actual iPhone, select a development team and choose a unique bundle ID in the target's Signing & Capabilities tab.

## Features

- Text is rendered to a short-lived, offscreen image. A custom Metal shader draws small textured pieces of that image flying into a rounded cloud.
- The concealed balance and percentage pill are drawn as independently animated Metal dots, with the reference white/lime palette, local touch repulsion and return-to-rest easing.
- The inverse transition assembles the amount from the same particle field.
- The text texture is removed from memory when a transition finishes; while hidden, the underlying UILabel remains hidden.
- Secondary figures are masked when privacy is enabled.
- Honors **Reduce Motion**, with an immediate, static privacy state.
- No packages, servers, keys, blockchain libraries or external dependencies. All balances are fake.

## Important files

| File | Purpose |
| --- | --- |
| `BalancePrivacyDemo/Sources/WalletDemoViewController.swift` | Demo home screen |
| `BalancePrivacyDemo/Sources/PrivacyBalanceView.swift` | State machine, taps, gestures, display link and text image |
| `BalancePrivacyDemo/Sources/BalanceParticlesMetalView.swift` | Metal data buffers, texture upload and particle motion |
| `BalancePrivacyDemo/Sources/BalanceParticles.metal` | Glyph tile transition and dust fragment shaders |

## Reference parameters

The shared preset in `BalanceParticlesMetalView.swift` uses the reference values: `size = 2.2`, `frequency = 0.75`, `spread = 24`, `travel = 10`, `turbulence = 1`, `stagger = 0.2`, `rotation = 40°`, `fragmentSize = 1.6`, `finalSize = 0.7`, `blendStart = 0.1` and `blendEnd = 0.75`. The percentage pill uses the same green as the original positive-balance state (`#7BFF9D`).

## Verification

The project and source were checked with `plutil -lint` and Swift typecheck for both simulator/device targets. A full Xcode build is currently blocked only by the local Xcode installation reporting a missing Metal Toolchain; install it with `xcodebuild -downloadComponent MetalToolchain`, then build the `BalancePrivacyDemo` scheme normally.
