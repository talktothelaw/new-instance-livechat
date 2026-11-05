#if canImport(UIKit)
import SwiftUI
import UIKit

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
    var ended: Bool = false
    let onRetry: (String) -> Void
    let onImageTap: (MessageAttachment) -> Void
    let onAnswer: (String, ElicitationAction, [String: ElicitationValue]?) async throws -> Void
    let onOpenStep: (URL) -> Bool
    var backgroundImage: OrgAppearanceBackgroundImage? = nil
    @Environment(\.chatColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var seenIds: Set<String> = []
    @State private var initialised = false
    @State private var userScrolledAway = false
    @State private var imageLoadTick = 0
    @State private var jumpToLatestTick = 0

    var body: some View {
        let items = MessageList.buildItems(from: messages)
        let unseen = newMessageIds

        ZStack(alignment: .bottom) {
            if let backgroundImage, let url = ChatBackgroundImage.url(for: backgroundImage) {
                ChatBackgroundImage(config: backgroundImage, url: url)
                    .id(url)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        // Anchor marker for the visual bottom (newest).
                        // Used to detect when the user is "at bottom" via
                        // PreferenceKey.
                        Color.clear
                            .frame(height: 1)
                            .id("__lac_bottom_anchor__")
                            .rotationEffect(.degrees(180))
                            .scaleEffect(x: -1, y: 1, anchor: .center)
                        if ended {
                            EndedNotice()
                                .id("ended")
                                .rotationEffect(.degrees(180))
                                .scaleEffect(x: -1, y: 1, anchor: .center)
                        }
                        if agentTyping {
                            TypingIndicator()
                                .padding(.leading, 36)
                                .id("typing")
                                .rotationEffect(.degrees(180))
                                .scaleEffect(x: -1, y: 1, anchor: .center)
                        }
                        ForEach(items) { item in
                            row(for: item)
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: BottomVisibilityKey.self,
                                value: BottomVisibility(frame: geo.frame(in: .named("lacScroll")))
                            )
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .coordinateSpace(name: "lacScroll")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollContainerHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )
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
                        if reduceMotion {
                            proxy.scrollTo(id, anchor: .bottom)
                        } else {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
                .onChange(of: imageLoadTick) { _ in
                    guard let id = messages.last?.id, !userScrolledAway else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
                .onChange(of: jumpToLatestTick) { _ in
                    guard let id = messages.last?.id else { return }
                    if reduceMotion {
                        proxy.scrollTo(id, anchor: .bottom)
                    } else {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                .onPreferenceChange(BottomVisibilityKey.self) { value in
                    updateScrollIntent(bottom: value)
                }
                .onPreferenceChange(ScrollContainerHeightKey.self) { h in
                    containerHeight = h
                }
            }
            if userScrolledAway && !unseen.isEmpty {
                ScrollToBottomPill(count: unseen.count) {
                    seenIds.formUnion(unseen)
                    userScrolledAway = false
                    jumpToLatestTick += 1
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private var newMessageIds: [String] {
        guard initialised else { return [] }
        return messages.compactMap { seenIds.contains($0.id) ? nil : $0.id }
    }

    @State private var containerHeight: CGFloat = 0

    private func updateScrollIntent(bottom: BottomVisibility) {
        guard containerHeight > 0 else { return }
        // The anchor sits at the visual bottom (post-rotation it's the top
        // edge of the reversed scroll content). Its frame.minY in scroll
        // coords tells us how far past the visible window the latest
        // message has been pushed by user dragging up.
        let offsetFromBottom = -bottom.frame.minY
        let threshold: CGFloat = 80
        let scrolledAway = offsetFromBottom > threshold
        if scrolledAway != userScrolledAway {
            userScrolledAway = scrolledAway
        }
    }

    @ViewBuilder
    private func row(for item: ListItem) -> some View {
        switch item.kind {
        case .day(let label):
            DaySeparator(label: label)
                .rotationEffect(.degrees(180))
                .scaleEffect(x: -1, y: 1, anchor: .center)
                .id(item.id)
        case .message(let msg):
            MessageRow(
                message: msg,
                onRetry: onRetry,
                onImageTap: onImageTap,
                onImageLoaded: { imageLoadTick += 1 },
                onAnswer: onAnswer,
                onOpenStep: onOpenStep
            )
            .rotationEffect(.degrees(180))
            // Flip horizontally so text and bubbles aren't mirrored after
            // the outer rotation. Two operations compose to identity on
            // glyphs while preserving the reverse-stack layout.
            .scaleEffect(x: -1, y: 1, anchor: .center)
            .id(msg.id)
        }
    }

    enum ListItemKind {
        case day(String)
        case message(ChatMessage)
    }

    struct ListItem: Identifiable {
        let id: String
        let kind: ListItemKind
    }

    /// Build the rendered list (reversed for visual bottom-up display)
    /// inserting day-divider rows between messages on different days.
    static func buildItems(from messages: [ChatMessage]) -> [ListItem] {
        guard !messages.isEmpty else { return [] }
        // Chronological order first so day-divider insertion logic is
        // straightforward; then reverse for the rotated ScrollView.
        var inserted: [ListItem] = []
        var lastKey: String?
        for msg in messages {
            let key = MessageRowHelpers.dayKey(msg.createdAt)
            if let key, key != lastKey {
                if let label = MessageRowHelpers.dayLabel(msg.createdAt) {
                    inserted.append(ListItem(id: "day:\(key)", kind: .day(label)))
                }
                lastKey = key
            }
            inserted.append(ListItem(id: msg.id, kind: .message(msg)))
        }
        return inserted.reversed()
    }
}

/// Preference key for tracking the bottom-anchor row's frame in the
/// scroll view's coordinate space. Used to detect "user scrolled away
/// from bottom".
struct BottomVisibility: Equatable {
    let frame: CGRect
}

struct BottomVisibilityKey: PreferenceKey {
    static let defaultValue = BottomVisibility(frame: .zero)
    static func reduce(value: inout BottomVisibility, nextValue: () -> BottomVisibility) {
        let next = nextValue()
        if next != defaultValue { value = next }
    }
}

struct ScrollContainerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ChatBackgroundImage: View {
    let config: OrgAppearanceBackgroundImage
    let url: URL
    @State private var image: UIImage?

    init(config: OrgAppearanceBackgroundImage, url: URL) {
        self.config = config
        self.url = url
        _image = State(initialValue: ImageCache.memoryPeek(url: url))
    }

    static func url(for config: OrgAppearanceBackgroundImage) -> URL? {
        guard config.enabled,
              let raw = config.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }

    var body: some View {
        GeometryReader { geo in
            if let image, geo.size.width > 0, geo.size.height > 0 {
                tiles(image, in: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .overlay(ChatColors.hex(config.overlayColor).opacity(Self.unit(config.overlayOpacity)))
            }
        }
        .clipped()
        .opacity(Self.unit(config.opacity))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil else { return }
        Task {
            let loaded = await ImageCache.shared.image(for: url)
            await MainActor.run {
                if let loaded { image = loaded }
            }
        }
    }

    private func tiles(_ image: UIImage, in box: CGSize) -> some View {
        let natural = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
        let scale = Self.scale(size: config.size, natural: natural, box: box)
        let tile = CGSize(width: natural.width * scale, height: natural.height * scale)
        let anchor = Self.anchor(config.position)
        let originX = (box.width - tile.width) * anchor.x
        let originY = (box.height - tile.height) * anchor.y
        let repeatStyle = config.repeatStyle.lowercased()
        let repeatX = repeatStyle == "repeat" || repeatStyle == "repeat-x"
        let repeatY = repeatStyle == "repeat" || repeatStyle == "repeat-y"
        let startX = repeatX ? Self.firstTile(origin: originX, step: tile.width) : originX
        let startY = repeatY ? Self.firstTile(origin: originY, step: tile.height) : originY
        let width = repeatX ? box.width - startX : tile.width
        let height = repeatY ? box.height - startY : tile.height
        return Image(uiImage: image)
            .resizable(resizingMode: .tile)
            .frame(width: width / scale, height: height / scale)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: startX, y: startY)
    }

    static func scale(size: String, natural: CGSize, box: CGSize) -> CGFloat {
        let fit = (width: box.width / natural.width, height: box.height / natural.height)
        switch size.lowercased() {
        case "contain": return max(min(fit.width, fit.height), 0.0001)
        case "auto": return 1
        default: return max(fit.width, fit.height, 0.0001)
        }
    }

    static func anchor(_ position: String) -> CGPoint {
        let words = position.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" })
        let x: CGFloat = words.contains("left") ? 0 : (words.contains("right") ? 1 : 0.5)
        let y: CGFloat = words.contains("top") ? 0 : (words.contains("bottom") ? 1 : 0.5)
        return CGPoint(x: x, y: y)
    }

    private static func firstTile(origin: CGFloat, step: CGFloat) -> CGFloat {
        let remainder = origin.truncatingRemainder(dividingBy: step)
        return remainder > 0 ? remainder - step : remainder
    }

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

struct ScrollToBottomPill: View {
    let count: Int
    let onTap: () -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colors.scrollToBottomIcon)
                .frame(width: 44, height: 44)
                .background(Circle().fill(colors.scrollToBottomBg).shadow(color: Color.black.opacity(0.18), radius: 10, y: 6))
                .overlay(Circle().strokeBorder(colors.hairline, lineWidth: 1))
                .overlay(badge, alignment: .topTrailing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            count > 1
                ? "\(count) new messages"
                : "1 new message"
        )
        .accessibilityHint("Double-tap to scroll to the latest message")
    }

    private var badge: some View {
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.heavy))
            .foregroundColor(colors.unreadBadgeText)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(colors.unreadBadgeBg))
            .offset(x: 4, y: -4)
            .accessibilityHidden(true)
    }
}

struct TypingIndicator: View {
    @Environment(\.chatColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    private let opacities: [Double] = [1, 0.7, 0.4]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(colors.typingDot)
                    .frame(width: 6, height: 6)
                    .scaleEffect(reduceMotion ? 1 : scaleFor(index: i))
                    .opacity(opacities[i])
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(RoundedCorners(tl: 16, tr: 16, bl: 6, br: 16).fill(colors.typingBg))
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent is typing")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func scaleFor(index: Int) -> CGFloat {
        let staggered = (phase + Double(index) * 0.15).truncatingRemainder(dividingBy: 1)
        return 0.6 + 0.4 * CGFloat(staggered)
    }
}

struct EndedNotice: View {
    @Environment(\.chatColors) private var colors

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colors.successColor)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 52 * 0.22, style: .continuous).fill(colors.successTint))
                .accessibilityHidden(true)
            Text(verbatim: "Conversation ended")
                .font(.headline.weight(.heavy))
                .foregroundColor(colors.receivedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

#endif
