# Changelog

## 0.4.1

- On iPad, `present(from:)` now opens the chat as a 400 x 620 pt panel in the bottom-right corner (bottom-left in right-to-left languages) over a dimmed backdrop, matching the web widget, instead of a full-screen column. The panel moves up when the keyboard opens. Tapping the backdrop closes the chat and reports `ChatCloseEvent` reason `gesture`. iPhone, and iPad apps in a narrow Split View or Slide Over window, keep the full-screen chat. React Native and Flutter pick this up through `present(from:)`.
- The example app gains an "Open chat (UIKit)" button that exercises `present(from:)`, logs close events, and shows its content on iPad (it previously rendered an empty split view).

## 0.4.0

- **Breaking**: the SDK now runs in exactly one of two exclusive auth modes. Pass `customerToken` (a chat token minted by your backend, sent as `Authorization: Bearer <token>`, with the customer identity taken only from its claims) or `apiKey` as the full `keyId:secret` pair (sent whole on `x-api-key`, for trusted internal apps only). Passing both or neither throws `LiveAndAiChatError` with code `E_CONFIG`, as does a key ID without a secret. `LiveAndAiChatConfig(apiKey:customerToken:...)` replaces the old `apiKey`-only initializer, and the raw credentials are no longer public properties; read `config.authMode` instead.
- **Breaking**: `ChatUser.customerToken` and `ChatUser.fromToken(_:)` are removed. Pass the token in the config instead.
- **Breaking**: `apiKey` is now sent whole. The SDK no longer strips the secret half of a `keyId:secret` key.
- New `setUserToken(_:)` swaps the customer token without rebuilding the SDK: later requests use the new token, the realtime subscription reconnects with it, and a failed initialization runs again. The saved conversation is kept unless the token belongs to a different customer. It throws `E_CONFIG` in API key mode or for a blank token.
- In customer token mode `setUser(_:)` is accepted but ignored, and `initCsAiChat` carries no customer fields.
- Every request (GraphQL, SSE reserve/stream/subscribe/complete, WebSocket upgrade) sends `x-newinstance-sdk: ios/0.4.0` and `User-Agent: LiveAndAiChat-iOS/0.4.0`. The WebSocket `connection_init` payload no longer carries a credential.
- A 401 or `UNAUTHENTICATED` response, including one delivered on the realtime subscription when a token expires or is revoked mid-session, is reported as an `.auth` error. The subscription no longer reconnects in a loop after an auth failure; call `setUserToken(_:)` to resume.
- `LiveAndAiChatConfig` redacts its credentials in `description`, `debugDescription` and `dump`.
- New `ChatErrorCode.invalidConfig` (`E_CONFIG`).
- `LiveAndAiChat.version` is now `0.4.0` (it previously still reported `0.2.0`).
- The example app no longer ships a committed API key. It fetches a customer token from a placeholder backend URL (`LAC_EXAMPLE_TOKEN_URL`) or, for trusted internal builds, reads a full key from `LAC_EXAMPLE_API_KEY`.
