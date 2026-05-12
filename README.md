# LiveAndAiChat iOS SDK

Native iOS SDK that mirrors the [`liveAndAiChat/`](../liveAndAiChat) web SDK
and the [`liveAndAiChat-android/`](../liveAndAiChat-android) Android SDK.

**Status:** Phase 2.A — foundation, transport, models, headless API.
**Chat UI ships in Phase 2.B.**

## Requirements

- iOS 14+
- Swift 5.9
- Xcode 15+

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/newinstance/live-and-ai-chat-ios.git", from: "0.1.0"),
```

### CocoaPods

```ruby
pod 'LiveAndAiChat', '~> 0.1.0'
```

## Quick start (headless)

```swift
import LiveAndAiChat
import Combine

let sdk = try LiveAndAiChat.Builder()
    .config(try LiveAndAiChatConfig(apiKey: "<keyId>"))
    .user(ChatUser(customerName: "Ada", customerEmail: "ada@example.com"))
    .build()

// Observe state with Combine (or use the LiveAndAiChatDelegate API).
sdk.$connectionState.sink { print("conn: \($0)") }.store(in: &bag)
sdk.$lifecycle.sink { print("lc: \($0)") }.store(in: &bag)

sdk.initialize()   // background, optional — warm the session
sdk.openChat()
sdk.sendMessage("Hello!")
```

## Public API surface

| Method | Web / Android equivalent |
|---|---|
| `LiveAndAiChat.Builder().config(_:).user(_:).build()` | `NInstanceChat.init(config)` / Kotlin Builder |
| `setUser(_:)` | embed config customer fields |
| `initialize()` | Android `initialize()` |
| `openChat()` | `widget.open()` |
| `closeChat()` | `widget.close()` |
| `sendMessage(_:)` | `sendCsCustomerMessage` mutation |
| `retryMessage(messageId:)` | Android `retryMessage` |
| `requestHandoff(reason:)` | Android `requestHandoff` |
| `sendTypingStart()` / `sendTypingStop()` | `useTyping` hook |
| `destroy()` | `widget.destroy()` |
| `$flowState`, `$messages`, `$conversation`, `$assignment`, `$agentTyping`, `$unreadCount`, `$orgConfig`, `$connectionState`, `$lifecycle` | StateFlow / publisher equivalents |

## Transport

Mirrors the Android / web SDKs: GraphQL over **HTTP POST** for queries / mutations,
plus subscriptions over **SSE** (default) or **WebSocket**.

- HTTP: `POST {baseUrl}/service`
- SSE: graphql-sse single-connection at `POST/GET/DELETE {baseUrl}/graphql/stream`
- WS: graphql-ws (`graphql-transport-ws`) at `wss://{host}/graphql/ws`

Reconnect: exponential backoff (`min(1s × 2^n, 30s)`) with ±50% jitter.
Heartbeat: server emits `csHeartbeat` every 10s; the client force-reconnects
after a 30s gap.

## Test

```bash
swift test
```

## What's not in this slice (Phase 2.B / 2.C)

- Built-in chat UI (SwiftUI views + theme application)
- Attachment / file upload (`requestPresignedUpload` flow)
- In-app fullscreen image viewer
- Notification chirp on incoming messages
- Background image rendering
- Fine-grained appearance application (theme is exposed as `OrgAppearance` on
  `orgConfig`; consumers can already read it, but the SDK doesn't render UI yet)

These follow in subsequent phases.
