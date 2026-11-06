# Thanos-Style Chat Deletion — iOS Demo

A standalone UIKit + Metal demo of a chat list where a deleted conversation breaks into tiny particles and scatters away, like the Thanos dust effect. The animation is attached to the chat row; after the particles disperse, the remaining rows close the gap.

The chat list is recreated from [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS), with its DustEffect particle logic adapted for chat deletion. The demo uses UIKit, `UITableView`, and Auto Layout instead of Telegram’s `ListView` and `ASDisplayNode`.

## DustEffect source

Adapted from Telegram-iOS: [`DustEffectLayer.swift`](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Components/DustEffect/Sources/DustEffectLayer.swift), [`DustEffectShaders.metal`](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Components/DustEffect/Metal/DustEffectShaders.metal), and [`DustFluidSimulation.swift`](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Components/DustEffect/Sources/DustFluidSimulation.swift). The layer coordinates particle lifetime and rendering; the Metal shaders and fluid simulation drive the dissolve effect.

## Run

1. Open `ThanosAnimationDemo.xcodeproj` in Xcode.
2. Select an iPhone simulator and run the `ThanosAnimationDemo` scheme.
3. Swipe a chat row to reveal **Delete** and tap it.
4. Choose **Delete just for me** to see the chat dissolve into particles.
5. To try the reversible flow, choose **Delete for me and …**, then confirm **Delete All**. The row dissolves and an **Undo** banner appears for five seconds.

The chat list is local demo data. Deletion does not contact Telegram or any server. The delete-for-everyone warning and undo banner demonstrate UI behavior only.

## Animation behavior

- The app captures the visible chat row and passes the snapshot to a Metal particle effect.
- Metal pipelines warm asynchronously after the chat list appears, with a short delay to keep initial rendering responsive.
- Particles scatter from the row as the table animates the deleted row closed.
- If Metal cannot initialize or render the effect, the app uses a tiled image-fragment animation as a fallback.
- The reversible delete flow displays an Undo action while the deletion window is open.
- Delete and Undo provide light haptic feedback.

## Main files

| File | Purpose |
| --- | --- |
| `ThanosAnimationDemo/Sources/ChatListDemoViewController.swift` | Chat list, delete confirmation, row snapshot, dissolve animation, row removal, and Undo banner |
| `ThanosAnimationDemo/Sources/DustEffectView.swift` | Metal view that renders the dust effect |
| `ThanosAnimationDemo/Sources/DustFluidSimulation.swift` | Particle and fluid simulation used by the effect |
| `ThanosAnimationDemo/Sources/DustEffectShaders.metal` | Metal compute and render shaders |
| `ThanosAnimationDemo/Sources/DustLoki.metal` and `ThanosAnimationDemo/Sources/loki_header.metal` | Random-number implementation used by the particle simulation |

## Requirements

- Xcode with the iOS SDK and Metal tools installed.
- iOS Simulator or a Metal-capable iPhone.
- No third-party packages, server, credentials, or Apple Developer membership for Simulator builds.
