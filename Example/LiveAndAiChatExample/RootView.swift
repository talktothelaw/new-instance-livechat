import SwiftUI
import LiveAndAiChat

/// Sample host UI. Mirrors the Android `HeadlessSampleActivity` flow:
///   1. Build a `LiveAndAiChat` instance with the dev API key.
///   2. Call `initialize()` on launch so the heavy config fetch happens
///      in the background.
///   3. Render an "Open chat" button. Tapping it presents the SDK's
///      built-in chat screen as a SwiftUI sheet (no UIKit required).
///   4. Show a status log so it's visible from the host whether the SSE
///      stream connects, messages arrive, etc.
struct RootView: View {

    @StateObject private var sdk: LiveAndAiChat
    @State private var showChat = false
    @State private var log: [String] = []

    init() {
        let config = try! LiveAndAiChatConfig(
            apiKey: Self.exampleApiKey,
            baseUrl: Self.exampleBaseUrl
        )
        let instance = try! LiveAndAiChat.Builder()
            .config(config)
            .user(ChatUser(
                customerName: "Sample User",
                customerEmail: "sample@example.com"
            ))
            .build()
        _sdk = StateObject(wrappedValue: instance)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                Button(action: openChat) {
                    HStack(spacing: 10) {
                        if sdk.lifecycle == .initializing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(buttonLabel)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(buttonBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(sdk.lifecycle == .initializing)
                Divider()
                Text("Event log")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
            .navigationTitle("LiveAndAiChat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showChat) {
            ChatScreen(
                sdk: sdk,
                onClose: {
                    sdk.closeChat()
                    showChat = false
                },
                onPickFile: { /* hooked up in Phase 2.B+ */ }
            )
        }
        .onAppear {
            sdk.initialize()
            attachListener()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(label: "Lifecycle", value: String(describing: sdk.lifecycle))
            statusRow(label: "Connection", value: String(describing: sdk.connectionState))
            statusRow(label: "Conversation", value: sdk.conversation?.id ?? "—")
            statusRow(label: "Messages", value: "\(sdk.messages.count)")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    private var buttonLabel: String {
        switch sdk.lifecycle {
        case .initializing, .notStarted: return "Connecting…"
        case .failed: return "Open chat (retry)"
        case .unavailable: return "Open chat (unavailable)"
        case .ready: return sdk.widgetOpen ? "Reopen chat" : "Open chat"
        }
    }

    private var buttonBg: Color {
        sdk.lifecycle == .initializing ? Color.gray : Color(red: 0.58, green: 0.20, blue: 0.92)
    }

    private func openChat() {
        sdk.openChat()
        showChat = true
    }

    private func attachListener() {
        let listener = ExampleListener { [self] line in
            DispatchQueue.main.async {
                log.append(line)
                if log.count > 200 { log.removeFirst(log.count - 200) }
            }
        }
        sdk.addDelegate(listener)
        ListenerHolder.shared.keepAlive(listener)
    }

    // MARK: - Dev configuration

    /// Replace before publishing — but for ngrok dev backends pointing at
    /// our local gql-server, the test key the team uses is hardcoded here.
    static let exampleApiKey = "sk_test_3ck4MFEog7TgV5QYOz9wZsNVQTtNRaHn"
    static let exampleBaseUrl = "https://emerging-fleet-vervet.ngrok-free.app"
}

/// Holds a strong reference to delegates so they aren't deallocated.
/// `LiveAndAiChat.addDelegate(_:)` uses an `NSHashTable.weakObjects()`
/// for the listener list (matches Android), so the host has to keep its
/// own strong reference.
final class ListenerHolder {
    static let shared = ListenerHolder()
    private var live: [AnyObject] = []
    func keepAlive(_ obj: AnyObject) { live.append(obj) }
}

final class ExampleListener: LiveAndAiChatDelegate {
    private let onLine: (String) -> Void
    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func didReceiveMessage(_ message: ChatMessage) {
        onLine("RECV [\(message.type.rawValue)] \(message.content)")
    }
    func didSendMessage(_ message: ChatMessage) {
        onLine("SENT \(message.content)")
    }
    func agentTypingDidChange(_ isTyping: Bool) {
        onLine("TYPING \(isTyping)")
    }
    func connectionStateDidChange(_ state: ConnectionState) {
        onLine("CONN \(state)")
    }
    func didEncounterError(_ error: LiveAndAiChatError) {
        onLine("ERR [\(error.type)] \(error.message)")
    }
}
