#if canImport(UIKit)
import SwiftUI

/// Reverse-anchored chat list. Mirrors the Android `MessageList`
/// composable: render the reversed message array inside a `ScrollView`
/// rotated 180°. Index 0 (newest message) sits at the visual bottom so
/// the chat opens at the latest message with no animated scroll.
///
/// Auto-scroll behaviour:
///   - On first paint: anchored at bottom by construction.
///   - On new message while the user is anchored at bottom: explicitly
///     scroll to the latest id (covers cases where the new bubble's
///     final height isn't known until its image loads).
///   - On image-load (`onImageLoaded` callback fired from
///     `MessageBubble`): re-anchor.
///   - When the user is intentionally scrolled up: show a pill with the
///     unseen-message count; tap to jump back.
struct MessageList: View {

    let messages: [ChatMessage]
    let agentTyping: Bool
    let onRetry: (String) -> Void
    let onImageTap: (MessageAttachment) -> Void
    @Environment(\.chatColors) private var colors

    @State private var seenIds: Set<String> = []
    @State private var initialised = false
    @State private var userScrolledAway = false
    @State private var imageLoadTick = 0

    var body: some View {
        let reversed = Array(messages.reversed())
        let unseen = newMessageIds

        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if agentTyping {
                            TypingIndicator()
                                .id("typing")
                                .rotationEffect(.degrees(180))
                                .scaleEffect(x: -1, y: 1, anchor: .center)
                        }
                        ForEach(reversed, id: \.id) { msg in
                            MessageRow(
                                message: msg,
                                onRetry: onRetry,
                                onImageTap: onImageTap,
                                onImageLoaded: { imageLoadTick += 1 }
                            )
                            .rotationEffect(.degrees(180))
                            // Flip horizontally so text and bubbles aren't
                            // mirrored after the outer rotation. Two
                            // operations compose to identity on glyphs
                            // while preserving the reverse-stack layout.
                            .scaleEffect(x: -1, y: 1, anchor: .center)
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .rotationEffect(.degrees(180))
                .scaleEffect(x: -1, y: 1, anchor: .center)
                .onAppear {
                    if !initialised && !messages.isEmpty {
                        seenIds = Set(messages.map { $0.id })
                        initialised = true
                    }
                }
                .onChange(of: messages.last?.id) { newId in
                    guard initialised, let id = newId else { return }
                    if seenIds.contains(id) { return }
                    if !userScrolledAway {
                        seenIds.insert(id)
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                .onChange(of: imageLoadTick) { _ in
                    guard let id = messages.last?.id, !userScrolledAway else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            if userScrolledAway && !unseen.isEmpty {
                ScrollToBottomPill(count: unseen.count) {
                    seenIds.formUnion(unseen)
                    userScrolledAway = false
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var newMessageIds: [String] {
        guard initialised else { return [] }
        return messages.compactMap { seenIds.contains($0.id) ? nil : $0.id }
    }
}

struct ScrollToBottomPill: View {
    let count: Int
    let onTap: () -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                Text(count > 1 ? "New messages (\(count))" : "New messages")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(colors.scrollToBottomIcon)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(colors.scrollToBottomBg))
            .shadow(color: Color.black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct TypingIndicator: View {
    @Environment(\.chatColors) private var colors
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(colors.typingDot)
                    .frame(width: 6, height: 6)
                    .scaleEffect(scaleFor(index: i))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(colors.typingBg))
        .padding(.leading, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func scaleFor(index: Int) -> CGFloat {
        let staggered = (phase + Double(index) * 0.15).truncatingRemainder(dividingBy: 1)
        return 0.6 + 0.4 * CGFloat(staggered)
    }
}

#endif
