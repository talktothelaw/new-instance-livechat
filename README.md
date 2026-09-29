# LiveAndAiChat iOS SDK

A native Swift SDK that drops a complete AI + live-agent chat experience into
your iOS app. Hosted by [newinstance.cloud](https://newinstance.cloud).

- SwiftUI chat screen with typing indicators, attachment thumbnails, image
  viewer, and per-message status receipts
- AI conversation with seamless handoff to a live human agent
- Photo Library + Files attachment pickers
- Two-tier image cache (memory + disk): repeat renders never re-fetch
- Resilient transport: HTTP/1.1-pinned Server-Sent Events with WebSocket fallback
- Offline-tolerant: silent gap-fill resync when the network drops events
- Light / dark themes, Dynamic Type, VoiceOver, Reduce Motion, iPad chat panel

## Requirements

- iOS 14.0+
- Swift 5.9 (Xcode 15+)

## Installation

### Swift Package Manager

In Xcode, open **File > Add Package Dependencies…** and enter:

```
https://github.com/talktothelaw/new-instance-livechat.git
```

Or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/talktothelaw/new-instance-livechat.git", from: "0.4.1"),
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
pod 'LiveAndAiChat', '~> 0.4.1'
```

## Quick start

Your backend mints a chat token for the signed-in customer (see
[Customer token mode](#customer-token-mode-recommended)); the app passes it to
the SDK:

```swift
import SwiftUI
import LiveAndAiChat

struct SupportButton: View {
    let sdk: LiveAndAiChat
    @State private var showChat = false

    var body: some View {
        Button("Talk to support") { showChat = true }
            .sheet(isPresented: $showChat) {
                ChatScreen(
                    sdk: sdk,
                    onClose: { showChat = false },
                    onPickFile: {}
                )
            }
            .onAppear { sdk.initialize() }
    }
}

func makeChat(tokenFromYourBackend: String) throws -> LiveAndAiChat {
    let config = try LiveAndAiChatConfig(customerToken: tokenFromYourBackend)
    return try LiveAndAiChat.Builder().config(config).build()
}
```

That's the entire integration. Brand colours, agent assignment, AI bot config,
and welcome message all come from the dashboard at
[`newinstance.cloud`](https://newinstance.cloud); there's nothing else to wire up.

### UIKit hosts

If you don't use SwiftUI, present the chat as a modal:

```swift
import LiveAndAiChat

class ViewController: UIViewController {
    var sdk: LiveAndAiChat?

    func startChat(tokenFromYourBackend: String) throws {
        sdk = try LiveAndAiChat.Builder()
            .config(LiveAndAiChatConfig(customerToken: tokenFromYourBackend))
            .build()
    }

    @IBAction func talkToSupport() {
        sdk?.present(from: self)
    }
}
```

On iPhone, `present(from:)` opens the chat full screen. On iPad it opens a 400 x 620 pt panel
in the bottom-right corner (bottom-left in right-to-left languages) over a dimmed backdrop,
like the web widget. Tapping the backdrop closes the chat with reason `gesture`. An iPad app
running in a narrow Split View or Slide Over window gets the full-screen chat.

## Authentication

The SDK runs in exactly **one** of two modes, chosen by what you pass to
`LiveAndAiChatConfig`:

| Mode | You pass | Sent on every request | Customer identity |
|---|---|---|---|
| Customer token (JWT) | `customerToken` | `Authorization: Bearer <token>` | the token's claims, verified by the server |
| API key | `apiKey: "keyId:secret"` | `x-api-key: keyId:secret` | `setUser(_:)` |

Every request (GraphQL, every SSE request, the WebSocket upgrade) also carries
`x-newinstance-sdk: ios/0.4.1`. Passing both `apiKey` and `customerToken`, or
neither, throws (see [Configuration errors](#configuration-errors)).
`config.authMode` tells you which mode is active.

### Customer token mode (recommended)

Use this for any app you ship to the public. Your secret key stays on your
server; the app only ever holds a short-lived token for one customer.

**1. Mint the token on your backend.** Call the REST API host with your full
`keyId:secret` key, server side only:

```
POST https://api.newinstance.cloud/api/v1/chat/sessions
x-api-key: sk_live_abc123:YOUR_SECRET_KEY
Content-Type: application/json

{
  "customerId": "usr_123",
  "customerName": "Ada Lovelace",
  "customerEmail": "ada@example.com",
  "customerPhone": "+44 20 7946 0958",
  "metadata": { "plan": "enterprise" },
  "expiresInSeconds": 3600
}
```

The response is `{ token, expiresAt, expiresInSeconds, session }`. Only
`customerId` and `customerName` are required. A minimal Node backend endpoint
that the app calls after sign-in:

```js
app.post('/chat/token', requireSignedInUser, async (req, res) => {
  const response = await fetch('https://api.newinstance.cloud/api/v1/chat/sessions', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': process.env.NEWINSTANCE_API_KEY,
    },
    body: JSON.stringify({
      customerId: req.user.id,
      customerName: req.user.name,
      customerEmail: req.user.email,
      expiresInSeconds: 3600,
    }),
  });
  const { token, expiresAt, expiresInSeconds } = await response.json();
  res.json({ token, expiresAt, expiresInSeconds });
});
```

`NEWINSTANCE_API_KEY` holds the full `keyId:secret` pair and never leaves your
server.

**2. Hand the token to the app:**

```swift
let token = try await myBackend.fetchChatToken()
let config = try LiveAndAiChatConfig(customerToken: token)
let sdk = try LiveAndAiChat.Builder().config(config).build()
sdk.initialize()
```

**3. Replace it when it expires:**

When the token expires or is revoked, the SDK reports an `auth` error
(`invalidIdentityToken`) and stops reconnecting. Fetch a fresh token from your
backend and swap it in:

```swift
try sdk.setUserToken(try await myBackend.fetchChatToken())
```

A customer holds one live session, so minting while their current token is
still valid returns `409`. To rotate before expiry, have your backend revoke
the current session first (`DELETE /api/v1/chat/sessions?customerId=...`) and
then mint.

`setUserToken(_:)` swaps the token without rebuilding the SDK: every later
request uses the new token, the realtime subscription reconnects with it, and
if initialization had failed (for example because the old token expired) it
runs again. The saved conversation is kept when the new token is for the same
customer (same `sub` claim); a token for a different customer clears it and
starts fresh. It throws `E_CONFIG` in API key mode or for a blank token.

Everything you put in the token request is signed into the token, so the chat
session already knows the customer before the app says anything:

```
customerId    -> the verified customer id
customerName  -> the name on the conversation and on every message
customerEmail -> also satisfies the merchant's "require email" setting
customerPhone -> shown to the agent
metadata      -> any extra context your agents should see
```

The server verifies the signature and takes the name, email and customer id
from the token's claims only. In this mode `setUser(_:)` is accepted but
ignored: nothing it carries is sent, so a tampered or repackaged app cannot
claim to be someone else, and the customer never sees a pre-chat form.

Sessions are managed over REST: `POST /api/v1/chat/sessions` to create,
`DELETE /api/v1/chat/sessions?customerId=...` on sign-out. You choose the
lifetime (60 seconds to 24 hours, default 1 hour) with `expiresInSeconds`.

A customer holds **one** live session at a time. Creating another while
theirs is valid returns `409` with the existing session; mint again once it
expires or after you revoke it. Revocation takes effect on the next request,
so an invalidated token stops working immediately even though its signature
is still valid. The token is the session: the identity is signed into it, and
the platform stores no copy. Decode the token if you need the name, email,
phone or metadata back.

### API key mode (trusted internal apps only)

**This mode ships your secret key inside the app.** Anyone who can download
the app can extract it and act as your organization. Use it only for trusted
or internal apps you control (staff tools, kiosks, internal test builds), never
for an app distributed to the public. Everything else should use
[customer token mode](#customer-token-mode-recommended).

```swift
let config = try LiveAndAiChatConfig(apiKey: "sk_live_abc123:YOUR_SECRET_KEY")
let sdk = try LiveAndAiChat.Builder()
    .config(config)
    .user(ChatUser(
        customerName: "Ada Lovelace",
        customerId: "user_42",
        customerEmail: "ada@example.com"
    ))
    .build()
```

The key must be the full `keyId:secret` pair from your dashboard at
[newinstance.cloud](https://newinstance.cloud) (**Settings > API keys**). It is
sent whole on `x-api-key`; a key ID on its own is rejected at construction.
Load it from your build configuration rather than committing it to source
control.

The customer comes from `setUser(_:)` (or `Builder.user(_:)`): `customerName`
is required, `customerEmail` and `customerId` are optional, and all three are
sent when the conversation starts. `customerId` in this mode is recorded on the
conversation for agent context and is deliberately **not** treated as
identity: it is never matched against other conversations, because trusting a
client-asserted id would let anyone resume someone else's chat by guessing it.

You can call `setUser` after `build()` if the customer becomes known later.
Switching to a different customer (a different `customerId`, or `customerEmail`
when there is no id) clears any saved conversation and starts fresh.
`setUserToken(_:)` is not available in this mode.

### Other options

```swift
let config = try LiveAndAiChatConfig(
    customerToken: token,
    transport: .sse,
    initialMessage: "Hi!"
)
```

`transport` is `.sse` (default), `.ws`, or `nil` to let the server decide.
`initialMessage` is optional and pre-seeds the first message.

`LiveAndAiChatConfig` never prints its credentials: `description`,
`debugDescription` and `dump` show `apiKey: <keyId>:***` or
`customerToken: ***`. The SDK's logs and errors never contain the secret or
the token.

### Configuration errors

Invalid configuration throws `LiveAndAiChatError` with `type == .validation`,
`code == "E_CONFIG"` (`ChatErrorCode.invalidConfig`) and `recoverable == false`:

| Situation | `message` |
|---|---|
| Both `apiKey` and `customerToken`, or neither (blank counts as absent) | `pass either apiKey (keyId:secret) or customerToken` |
| `apiKey` without a `:` or with an empty key ID or secret | `apiKey must be keyId:secret, or use customerToken` |
| `setUserToken` in API key mode | `setUserToken is only available when the SDK is configured with customerToken` |
| `setUserToken` with a blank token | `customerToken must not be blank` |

## Sending messages and attachments

```swift
sdk.sendMessage("Hi, I have a question.")

let id = sdk.attachFile(
    data: fileData,
    name: "screenshot.png",
    mimeType: "image/png",
    previewUri: localFileURL.absoluteString
)

sdk.attach(
    AttachmentRequest(
        source: .filePath(pickedURL.absoluteString),
        name: "receipt.pdf",
        mimeType: "application/pdf",
        declaredSize: pickedSize,
        metadata: ["origin": "orders-screen"]
    )
)

sdk.removeAttachment(id: id)
sdk.clearAttachments()

sdk.retryMessage(messageId: failedMessage.id)
sdk.requestHandoff(reason: "billing question")
sdk.sendTypingStart()
```

`attachFile` takes bytes you already hold in memory and returns the queue-item
id. `attach` accepts any other source: base64, data URIs, file URLs and paths
(security-scoped picker URLs handled), and remote URLs when the config enables
`allowRemoteAttachmentUrls`. `AttachmentSource.detect(_:)` is the safe `auto`
mode for strings. The next `sendMessage()` drains the queue and includes
uploaded attachments; a message is never sent with an attachment that hasn't
finished uploading. Removing an attachment cancels an in-flight upload, and
`sendTypingStart()` is followed automatically by `sendTypingStop()` after idle.

Validation runs before anything is queued: base64 must decode, file URLs
must be readable, data must be non-empty and at most 25 MB, MIME must be
one of png/jpeg/webp/gif/pdf, a wrong `declaredSize` is rejected as
corruption, and the extension must agree with the MIME type. Reads and
uploads run off the main thread; progress and results stream through the
attachment queue and `attachmentDidUpdate`. Attachment contents are
never logged, and upload requests never carry your credentials.

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
`pendingAttachmentCount`, and `metadata` (SDK version + platform), and
never message contents, credentials, or attachment data. `closeChat()`
also dismisses the presented chat controller. Delegates are held
weakly, so they clean up automatically when your object deallocates.

## Customisation

The chat resolves its colours from three layers:

```
dashboard theme  >  your local theme  >  the SDK's built-in theme
```

Branding (colours, logo, company name, welcome message) is configured from your
dashboard at [newinstance.cloud](https://newinstance.cloud); the SDK fetches it on
launch and applies it automatically. You do not need to ship colour values in
the app.

If you want a say, pass a local theme. It is ranked **below** anything the
dashboard sets and **above** the built-in palette, merged token by token, so
setting one colour does not discard the others:

```swift
let config = try LiveAndAiChatConfig(
    customerToken: token,
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
sdk.addDelegate(MyHandler())

sdk.$lifecycle
    .sink { lifecycle in
        if lifecycle == .failed {
            showRetryButton()
        }
    }
    .store(in: &bag)
```

When `lifecycle` is `.failed`, calling `sdk.initialize()` tries again.
`LiveAndAiChatError.type` is one of `.network` / `.validation` / `.auth` /
`.system`. `error.recoverable == true` means a retry has a chance of
succeeding.

`error.code` carries the raw GraphQL or transport code; call
`error.sdkCode(usingIdentityToken:)` to normalise onto the stable
`ChatErrorCode` vocabulary shared with every other chat SDK. Pass
`usingIdentityToken: config.authMode == .customerToken`: an auth failure alone
cannot tell a rejected key from a rejected token, and the two need different
fixes. Nothing on this channel is shown inside the chat interface, and it
never contains the API key secret, the customer token, or customer data.

```swift
func didEncounterError(_ error: LiveAndAiChatError) {
    switch error.sdkCode(usingIdentityToken: config.authMode == .customerToken) {
    case ChatErrorCode.invalidIdentityToken: refreshChatToken()
    case ChatErrorCode.invalidPublicKey: reportMisconfiguration()
    default: break
    }
}
```

Auth failures (HTTP 401, or a GraphQL error with `extensions.code ==
"UNAUTHENTICATED"`) arrive with `type == .auth`. That includes a token that
expires or is revoked mid-session: the realtime subscription reports it, the
SDK emits the `.auth` error and stops reconnecting with that token. Call
`setUserToken(_:)` with a fresh token to resume; the SDK reconnects and, if
initialization had failed, runs it again.

| `ChatErrorCode` | What went wrong |
|---|---|
| `invalidConfig` (`E_CONFIG`) | The configuration or a `setUserToken` call was invalid; thrown synchronously, see [Configuration errors](#configuration-errors) |
| `missingWidgetKey` | No API key was supplied |
| `invalidPublicKey` | The key was rejected: wrong key, wrong environment, revoked, expired |
| `chatConfigUnavailable` | The key is fine, but the organization has no chat configuration |
| `chatDisabled` | Chat is switched off in the dashboard |
| `configFetchFailed` | Remote configuration could not be loaded; the local/built-in theme is in use |
| `invalidIdentityToken` | The customer token was malformed, expired, revoked, or signed for another organization |
| `networkError` | The backend could not be reached |
| `transportError` | The realtime connection dropped |
| `chatInitializationFailed` | The conversation could not be started |
| `messageSendFailed` | A message could not be delivered |
| `attachmentFailed` | An attachment could not be uploaded |
| `serverError` | The backend returned something unusable |

## Sample app

The repository's `Example/` directory contains a runnable sample app
demonstrating the full integration. Open `Example/LiveAndAiChatExample.xcodeproj`
in Xcode 15+. No credential is committed. Set the `LAC_EXAMPLE_TOKEN_URL`
environment variable in the scheme to a backend endpoint that returns
`{ "token": "..." }` (customer token mode, with a **Refresh token** button that
calls `setUserToken`), or, for a trusted internal build only, set
`LAC_EXAMPLE_API_KEY` (or the `LACExampleApiKey` Info.plist entry, empty by
default) to a full `keyId:secret` key.

## License

MIT. See [LICENSE](./LICENSE).
