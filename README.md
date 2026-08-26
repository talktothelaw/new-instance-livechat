# LiveAndAiChat — iOS SDK

A native Swift SDK that drops a complete AI + live-agent chat experience into
your iOS app. Hosted by [newinstance.cloud](https://newinstance.cloud).

- SwiftUI chat screen with typing indicators, attachment thumbnails, image
  viewer, and per-message status receipts
- AI conversation with seamless handoff to a live human agent
- Photo Library + Files attachment pickers
- Two-tier image cache (memory + disk) — repeat renders never re-fetch
- Resilient transport: HTTP/1.1-pinned Server-Sent Events with WebSocket fallback
- Offline-tolerant — silent gap-fill resync when the network drops events
- Light / dark themes, Dynamic Type, VoiceOver, Reduce Motion, iPad layout

## Requirements

- iOS 14.0+
- Swift 5.9 (Xcode 15+)

## Installation

### Swift Package Manager

In Xcode → **File → Add Package Dependencies…** and enter:

```
https://github.com/talktothelaw/new-instance-livechat.git
```

Or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/talktothelaw/new-instance-livechat.git", from: "0.2.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "LiveAndAiChat", package: "liveandaichat-ios"),
        ]
    )
]
```

### CocoaPods

```ruby
pod 'LiveAndAiChat', '~> 0.2.0'
```

## Quick start

```swift
import SwiftUI
import LiveAndAiChat

@main
struct MyApp: App {
    @StateObject private var sdk: LiveAndAiChat = {
        let config = try! LiveAndAiChatConfig(apiKey: "sk_live_…")
        return try! LiveAndAiChat.Builder()
            .config(config)
            .user(ChatUser(customerName: "Ada", customerEmail: "ada@example.com"))
            .build()
    }()

    @State private var showChat = false

    var body: some Scene {
        WindowGroup {
            Button("Talk to support") { showChat = true }
                .sheet(isPresented: $showChat) {
                    ChatScreen(
                        sdk: sdk,
                        onClose: { showChat = false },
                        onPickFile: { /* present your attachment picker */ }
                    )
                }
                .onAppear { sdk.initialize() }
        }
    }
}
```

That's the entire integration. Brand colours, agent assignment, AI bot config,
and welcome message all come from the dashboard at
[`newinstance.cloud`](https://newinstance.cloud) — there's nothing else to wire up.

### UIKit hosts

If you don't use SwiftUI, present the chat as a modal:

```swift
import LiveAndAiChat

class ViewController: UIViewController {
    let sdk = try! LiveAndAiChat.Builder()
        .config(try! LiveAndAiChatConfig(apiKey: "sk_live_…"))
        .user(ChatUser(customerName: "Ada"))
        .build()

    @IBAction func talkToSupport() {
        sdk.present(from: self)
    }
}
```

## Configuration

`LiveAndAiChatConfig` only requires an API key. Get one from your dashboard at
[newinstance.cloud](https://newinstance.cloud) → **Settings → API keys**.

```swift
let config = try LiveAndAiChatConfig(
    apiKey: "sk_live_…",       // required — keyId only, never embed the secret half
    transport: .sse,           // .sse (default), .ws, or nil to let the server decide
    initialMessage: "Hi!"      // optional — pre-seeds the first message
)
```

### User identity

`apiKey` is the publishable widget key **ID**. The `keyId:secret` form belongs
on your server only, including for minting the identity token below.

**Anonymous or self-declared:**

```swift
sdk.setUser(ChatUser(
    customerName: "Ada Lovelace",     // required
    customerEmail: "ada@example.com", // optional
    customerId: "user_42"             // optional; see the caveat below
))
```

**Verified (recommended when you have accounts).** Have your backend mint a
chat identity token and hand it to the app. The token is the identity, so
nothing else is needed:

```swift
// Your backend, with the SECRET key, typically at sign-in:
//   POST https://api.newinstance.cloud/api/v1/chat/sessions
//   x-api-key: sk_live_abc123:YOUR_SECRET_KEY
//   { "customerId": "usr_123", "customerName": "Ada Lovelace",
//     "customerEmail": "ada@example.com", "customerPhone": "+44 20 7946 0958",
//     "metadata": { "plan": "enterprise" }, "expiresInSeconds": 21600 }
//   -> { token, expiresAt, session: { sessionId, ... } }

sdk.setUser(ChatUser.fromToken(tokenFromYourBackend))
```

Everything you put in that payload is signed into the token, so the chat
session already knows the customer before the app says anything:

```
customerId    -> the verified customer id
customerName  -> the name on the conversation and on every message
customerEmail -> also satisfies the merchant's "require email" setting
customerPhone -> shown to the agent
metadata      -> any extra context your agents should see
```

The client then passes **one string**. It never repeats the name, never
repeats the email, and is never shown a pre-chat form.

The server verifies the signature and derives the name, email and customer id
from the token's claims, so a tampered or repackaged app cannot claim to be
someone else.

`customerId` passed **without** a token is recorded on the conversation for
agent context and is deliberately **not** treated as identity: it is never
matched against other conversations, because trusting a client-asserted id
would let anyone resume someone else's chat by guessing it.

You can call `setUser` after `build()` if identity becomes available later
(post-login). Switching to a different customer clears any saved conversation
and starts fresh. Refreshing a token for the *same* customer does not count as
a switch: the SDK compares the token's subject, not the token string.

Tokens expire (one hour by default). A rejected one surfaces as
`ChatErrorCode.invalidIdentityToken`; mint a fresh one.

Sessions are managed over REST: `POST /api/v1/chat/sessions` to create,
`DELETE /api/v1/chat/sessions?customerId=...` on sign-out. You choose the
lifetime (60 seconds to 24 hours, default 1 hour) with `expiresInSeconds`.

A customer holds **one** live session at a time. Creating another while
theirs is valid returns `409` with the existing session; mint again once it
expires or after you revoke it. Revocation takes effect on the next request,
so an invalidated token stops working immediately even though its signature
is still valid.

The token is the session: the identity is signed into it, and the platform
stores no copy. Decode the token if you need the name, email, phone or
metadata back.


## Sending messages and attachments

```swift
sdk.sendMessage("Hi, I have a question.")

// Bytes you already hold in memory (returns the queue-item id):
let id = sdk.attachFile(
    data: fileData,
    name: "screenshot.png",
    mimeType: "image/png",
    previewUri: localFileURL.absoluteString
)

// Any other source — base64, data URIs, file URLs/paths (security-scoped
// picker URLs handled), and (when the config enables
// allowRemoteAttachmentUrls) remote URLs. `AttachmentSource.detect(_:)`
// is the safe `auto` mode for strings:
sdk.attach(
    AttachmentRequest(
        source: .filePath(pickedURL.absoluteString),
        name: "receipt.pdf",
        mimeType: "application/pdf",
        declaredSize: pickedSize,
        metadata: ["origin": "orders-screen"]
    )
)
// Next sendMessage() drains the queue and includes uploaded attachments —
// a message is never sent with an attachment that hasn't finished uploading.

// Cancel / clear (cancelling stops an in-flight upload):
sdk.removeAttachment(id: id)
sdk.clearAttachments()

sdk.retryMessage(messageId: failedMessage.id)
sdk.requestHandoff(reason: "billing question")
sdk.sendTypingStart()  // automatically followed by sendTypingStop after idle
```

Validation runs before anything is queued: base64 must decode, file URLs
must be readable, data must be non-empty and at most 25 MB, MIME must be
one of png/jpeg/webp/gif/pdf, a wrong `declaredSize` is rejected as
corruption, and the extension must agree with the MIME type. Reads and
uploads run off the main thread; progress and results stream through the
attachment queue and `attachmentDidUpdate`. Attachment contents are
never logged.

## Observing state

`LiveAndAiChat` is an `ObservableObject`. Bind any `@Published` property to your
SwiftUI views or subscribe with Combine:

| Property | Type | What it tells you |
|---|---|---|
| `lifecycle` | `ChatSdkLifecycle` | `.notStarted` / `.initializing` / `.ready` / `.unavailable` / `.failed` |
| `connectionState` | `ConnectionState` | `.idle` / `.connecting` / `.connected` / `.disconnected` / `.offline` |
| `messages` | `[ChatMessage]` | the conversation, ordered |
| `conversation` | `Conversation?` | server-side conversation status |
| `assignment` | `Assignment?` | live-agent assignment state |
| `agentTyping` | `Bool` | true while the agent is typing |
| `unreadCount` | `Int` | unread inbound messages while the widget is closed |
| `orgConfig` | `OrgChatConfig?` | merchant branding + appearance + settings |
| `widgetOpen` | `Bool` | true between `openChat()` and `closeChat()` |

For UIKit / closure-based hosts, use the delegate:

```swift
class MyHandler: LiveAndAiChatDelegate {
    func didReceiveMessage(_ m: ChatMessage) { … }
    func didSendMessage(_ m: ChatMessage) { … }
    func agentTypingDidChange(_ t: Bool) { … }
    func connectionStateDidChange(_ s: ConnectionState) { … }
    func didEncounterError(_ e: LiveAndAiChatError) { … }
    func unreadCountDidChange(_ count: Int) { … }
    func attachmentDidUpdate(_ a: QueuedAttachment) { … }
    func chatDidClose(_ event: ChatCloseEvent) { … }
}

sdk.addDelegate(MyHandler())
```

## The chat-close event

`chatDidClose` fires **exactly once per chat presentation**, whichever way
the built-in chat screen goes away:

| Path | `reason` | `initiator` |
|---|---|---|
| In-chat X button | `.closeButton` | `.user` |
| Sheet/gesture dismissal | `.gesture` | `.user` |
| `closeChat()` | `.programmatic` | `.host` |
| `destroy()` | `.sessionEnded` | `.sdk` |
| Host dismissing/navigating the screen away | `.hostNavigation` | `.host` |

The event carries `timestamp`, `conversationId`, `assignmentId`,
`channel`, `previousState`, `unreadCount`, `hasDraft`,
`pendingAttachmentCount`, and `metadata` (SDK version + platform) —
never message contents, credentials, or attachment data. `closeChat()`
now also dismisses the presented chat controller. Delegates are held
weakly, so they clean up automatically when your object deallocates.

## Customisation

The chat resolves its colours from three layers:

```
dashboard theme  >  your local theme  >  the SDK's built-in theme
```

Branding (colours, logo, company name, welcome message) is configured from your
dashboard at [newinstance.cloud](https://newinstance.cloud) — the SDK fetches it on
launch and applies it automatically. You do not need to ship colour values in
the app.

If you want a say, pass a local theme. It is ranked **below** anything the
dashboard sets and **above** the built-in palette, merged token by token, so
setting one colour does not discard the others:

```swift
let config = try LiveAndAiChatConfig(
    apiKey: "sk_live_…",
    theme: ChatThemeOverride(mode: .dark, sentBubble: "#16A34A")
)
```

Every `ChatThemeOverride` field is optional; colours are hex strings
(`#RRGGBB` or `#AARRGGBB`). An unparseable value is ignored rather than
throwing. `mode` is only a preference: the dashboard's explicit light/dark
wins, its `auto` defers to yours, and if nobody pins one the system colour
scheme decides.

If no dashboard configuration is reachable, your local theme still applies and
the built-in palette fills the rest, so the chat is always fully themed, even
offline. You get a `configFetchFailed` warning on the error channel.

## Privacy

The SDK does not require any `Info.plist` permission keys. The built-in
chat screen picks attachments with `UIDocumentPickerViewController`
(out-of-process; no usage-description prompt). The bundled Example app
additionally demonstrates `PHPickerViewController`, which is likewise
out-of-process.

If you save attachments to the device's Photos library from the in-app image
viewer, add:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>So you can save chat images to Photos.</string>
```

## Error handling

```swift
sdk.addDelegate(MyHandler())  // see above

// Or via Combine:
sdk.$lifecycle
    .sink { lifecycle in
        if lifecycle == .failed {
            // initialize() failed — show retry CTA
            // sdk.initialize() will try again
        }
    }
    .store(in: &bag)
```

`LiveAndAiChatError.type` is one of `.network` / `.validation` / `.auth` /
`.system`. `error.recoverable == true` means a retry has a chance of
succeeding.

`error.code` carries the raw GraphQL or transport code; call
`error.sdkCode(usingIdentityToken:)` to normalise onto the stable
`ChatErrorCode` vocabulary shared with every other chat SDK. Nothing on this
channel is shown inside the chat interface, and it never contains the API key,
the identity token, or customer data.

```swift
func didEncounterError(_ error: LiveAndAiChatError) {
    switch error.sdkCode(usingIdentityToken: true) {
    case ChatErrorCode.invalidIdentityToken: refreshChatToken()
    case ChatErrorCode.invalidPublicKey: reportMisconfiguration()
    default: break
    }
}
```

| `ChatErrorCode` | What went wrong |
|---|---|
| `missingWidgetKey` | No API key was supplied |
| `invalidPublicKey` | The key was rejected: wrong key, wrong environment, revoked, expired |
| `chatConfigUnavailable` | The key is fine, but the organization has no chat configuration |
| `chatDisabled` | Chat is switched off in the dashboard |
| `configFetchFailed` | Remote configuration could not be loaded; the local/built-in theme is in use |
| `invalidIdentityToken` | The token was malformed, expired, or signed for another organization |
| `networkError` | The backend could not be reached |
| `transportError` | The realtime connection dropped |
| `chatInitializationFailed` | The conversation could not be started |
| `messageSendFailed` | A message could not be delivered |
| `attachmentFailed` | An attachment could not be uploaded |
| `serverError` | The backend returned something unusable |

Pass `usingIdentityToken: true` when the SDK was configured with a token: an
auth failure cannot otherwise tell a rejected key from a rejected token, and
the two need different fixes.

## Sample app

The repository's `Example/` directory contains a runnable sample app
demonstrating the full integration. Open `Example/LiveAndAiChatExample.xcodeproj`
in Xcode 15+.

## License

MIT — see [LICENSE](./LICENSE).
