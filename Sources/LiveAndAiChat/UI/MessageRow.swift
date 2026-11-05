#if canImport(UIKit)
import SwiftUI

/// Renders one message row: optional sender label, optional text bubble,
/// attachments rendered OUTSIDE the bubble (matches the web /
/// Android implementations). A FAILED message shows a tap-to-retry
/// affordance below the bubble.
struct MessageRow: View {

    let message: ChatMessage
    let onRetry: (String) -> Void
    let onImageTap: (MessageAttachment) -> Void
    let onImageLoaded: () -> Void
    let onAnswer: (String, ElicitationAction, [String: ElicitationValue]?) async throws -> Void
    let onOpenStep: (URL) -> Bool
    @Environment(\.chatColors) private var colors

    var body: some View {
        // System messages render as centered text between hairlines with
        // no bubble, no sender label, no timestamp.
        if message.type == .system {
            SystemMessageRow(content: message.content)
        } else if let step = message.elicitation {
            stepBody(step)
        } else {
            chatMessageBody
        }
    }

    private func stepBody(_ step: Elicitation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            MessageAvatar(type: message.type, name: senderLabel ?? "")
            VStack(alignment: .leading, spacing: 4) {
                if let line = senderLine {
                    SenderLine(text: line)
                }
                ElicitationCard(
                    prompt: message.content,
                    elicitation: step,
                    onAnswer: { action, content in try await onAnswer(message.id, action, content) },
                    onOpen: onOpenStep
                )
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(colors.background)
                        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
                )
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.hairline, lineWidth: 1))
            }
            .frame(maxWidth: 320, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chatMessageBody: some View {
        let isCustomer = message.type == .customer
        let hasContent = !message.content.isEmpty
        let hasAttachments = !message.attachments.isEmpty

        if isCustomer {
            VStack(alignment: .trailing, spacing: 4) {
                if hasContent {
                    TextBubble(message: message, isCustomer: true)
                    if hasAttachments {
                        attachmentsBlock(isCustomer: true, hasContent: true)
                    }
                } else if hasAttachments {
                    VStack(alignment: .trailing, spacing: 6) {
                        attachmentsBlock(isCustomer: true, hasContent: false)
                        SentFooter(message: message)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                    }
                    .padding(4)
                    .background(RoundedCorners(tl: 18, tr: 18, bl: 18, br: 6).fill(colors.sentBubble))
                }
                if message.status == .failed {
                    Button { onRetry(message.id) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Failed · tap to retry")
                            Image(systemName: "arrow.clockwise")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(colors.errorColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Message failed to send")
                    .accessibilityHint("Double-tap to retry")
                }
            }
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                MessageAvatar(type: message.type, name: senderLabel ?? "")
                VStack(alignment: .leading, spacing: 4) {
                    if let line = senderLine {
                        SenderLine(text: line)
                            .accessibilityHidden(true)  // rolled into the bubble's label
                    }
                    if hasContent {
                        TextBubble(message: message, isCustomer: false)
                    }
                    if hasAttachments {
                        attachmentsBlock(isCustomer: false, hasContent: hasContent)
                    }
                }
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private func attachmentsBlock(isCustomer: Bool, hasContent: Bool) -> some View {
        AttachmentsBlock(
            attachments: message.attachments,
            isCustomer: isCustomer,
            topPadding: hasContent ? 2 : 0,
            onImageTap: onImageTap,
            onImageLoaded: onImageLoaded
        )
    }

    /// Single VoiceOver utterance per message row. Combines sender,
    /// content, attachments and status so the user hears the row as
    /// one logical unit rather than as a half-dozen disjoint Texts.
    private var accessibilitySummary: String {
        var parts: [String] = []
        switch message.type {
        case .customer: parts.append("You said:")
        case .agent:    parts.append("\(message.sender?.senderName ?? "Agent") said:")
        case .ai:       parts.append("AI assistant said:")
        case .system:   parts.append("System message:")
        }
        if !message.content.isEmpty {
            parts.append(message.content)
        }
        if !message.attachments.isEmpty {
            let imgs = message.attachments.filter { MessageRowHelpers.isImage($0) }.count
            let files = message.attachments.count - imgs
            if imgs > 0 {
                parts.append("\(imgs) photo\(imgs == 1 ? "" : "s") attached")
            }
            if files > 0 {
                parts.append("\(files) file\(files == 1 ? "" : "s") attached")
            }
        }
        if let ts = MessageRowHelpers.formatTimestamp(message.createdAt) {
            parts.append("at \(ts)")
        }
        if message.type == .customer {
            switch message.status {
            case .failed:    parts.append("Failed to send")
            case .read:      parts.append("Read")
            case .delivered: parts.append("Delivered")
            case .sent:      parts.append("Sent")
            }
        }
        return parts.joined(separator: " ")
    }

    private var senderLabel: String? {
        switch message.type {
        case .ai: return "AI"
        case .agent:
            let raw = message.sender?.senderName ?? "Agent"
            return ChatHeader.titleCase(raw)
        case .system, .customer: return nil
        }
    }

    private var senderLine: String? {
        guard let label = senderLabel else { return nil }
        guard let ts = MessageRowHelpers.formatTimestamp(message.createdAt) else { return label }
        return "\(label) · \(ts)"
    }
}

private struct SenderLine: View {
    let text: String
    @Environment(\.chatColors) private var colors

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundColor(colors.receivedTimestamp)
            .lineLimit(1)
    }
}

struct MessageAvatar: View {
    let type: MessageType
    let name: String
    @Environment(\.chatColors) private var colors

    var body: some View {
        Group {
            if type == .ai {
                let points = HeaderBackdrop.gradientPoints(width: 28, height: 28)
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colors.headerPrimaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 28 * 0.22, style: .continuous)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [colors.headerStops.glow, colors.headerBackground]),
                                startPoint: points.start,
                                endPoint: points.end
                            ))
                    )
            } else {
                Text(verbatim: MessageRowHelpers.initials(name))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(colors.receivedText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(colors.agentAvatar))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Centered system notice rendered inline with the message stream
/// between two hairlines. No bubble, no sender label, no timestamp.
private struct SystemMessageRow: View {
    let content: String
    @Environment(\.chatColors) private var colors

    var body: some View {
        HStack(spacing: 10) {
            hairline
            Text(content)
                .font(.footnote)
                .foregroundColor(colors.systemMessageText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            hairline
        }
        .frame(maxWidth: .infinity)
    }

    private var hairline: some View {
        Rectangle()
            .fill(colors.hairline)
            .frame(minWidth: 16, maxWidth: .infinity)
            .frame(height: 1)
    }
}

private struct TextBubble: View {
    let message: ChatMessage
    let isCustomer: Bool
    @Environment(\.chatColors) private var colors

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(message.content)
                .font(.callout)
                .foregroundColor(isCustomer ? colors.sentText : colors.receivedText)
                .fixedSize(horizontal: false, vertical: true)
            if isCustomer {
                SentFooter(message: message)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleShape.fill(isCustomer ? colors.sentBubble : colors.receivedBubble))
        .frame(maxWidth: 280, alignment: isCustomer ? .trailing : .leading)
    }

    private var bubbleShape: RoundedCorners {
        isCustomer
            ? RoundedCorners(tl: 18, tr: 18, bl: 18, br: 6)
            : RoundedCorners(tl: 18, tr: 18, bl: 6, br: 18)
    }
}

private struct SentFooter: View {
    let message: ChatMessage
    @Environment(\.chatColors) private var colors

    var body: some View {
        HStack(spacing: 4) {
            if let ts = MessageRowHelpers.formatTimestamp(message.createdAt) {
                Text(ts)
                    .font(.caption2)
            }
            statusIcon
        }
        .foregroundColor(colors.sentTimestamp)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch message.status {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
        case .sent:
            tick(double: false)
        case .delivered:
            tick(double: true)
                .opacity(0.6)
        case .read:
            tick(double: true)
        }
    }

    private func tick(double: Bool) -> some View {
        TickShape(double: double)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 14, height: 14)
    }
}

struct TickShape: Shape {
    let double: Bool

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        if double {
            path.move(to: p(18, 6)); path.addLine(to: p(7, 17)); path.addLine(to: p(2, 12))
            path.move(to: p(22, 10)); path.addLine(to: p(14.5, 17.5)); path.addLine(to: p(13, 16))
        } else {
            path.move(to: p(20, 6)); path.addLine(to: p(9, 17)); path.addLine(to: p(4, 12))
        }
        return path
    }
}

/// 4-corner rounded rectangle. SwiftUI's stock `RoundedRectangle` doesn't
/// support asymmetric corners until iOS 16+; we hand-roll a path so the
/// SDK can build for iOS 14.
struct RoundedCorners: Shape {
    var tl: CGFloat = 0
    var tr: CGFloat = 0
    var bl: CGFloat = 0
    var br: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let tlc = min(tl, min(w, h) / 2)
        let trc = min(tr, min(w, h) / 2)
        let blc = min(bl, min(w, h) / 2)
        let brc = min(br, min(w, h) / 2)
        path.move(to: CGPoint(x: tlc, y: 0))
        path.addLine(to: CGPoint(x: w - trc, y: 0))
        path.addArc(
            center: CGPoint(x: w - trc, y: trc),
            radius: trc, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: w, y: h - brc))
        path.addArc(
            center: CGPoint(x: w - brc, y: h - brc),
            radius: brc, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: blc, y: h))
        path.addArc(
            center: CGPoint(x: blc, y: h - blc),
            radius: blc, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: tlc))
        path.addArc(
            center: CGPoint(x: tlc, y: tlc),
            radius: tlc, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Attachments

struct AttachmentsBlock: View {
    let attachments: [MessageAttachment]
    let isCustomer: Bool
    let topPadding: CGFloat
    let onImageTap: (MessageAttachment) -> Void
    let onImageLoaded: () -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        let split = MessageRowHelpers.splitAttachments(attachments)
        VStack(alignment: isCustomer ? .trailing : .leading, spacing: 4) {
            if !split.images.isEmpty {
                ImageGrid(
                    images: split.images,
                    isCustomer: isCustomer,
                    onImageTap: onImageTap,
                    onImageLoaded: onImageLoaded
                )
            }
            ForEach(split.files, id: \.url) { att in
                FileAttachmentRow(attachment: att, isCustomer: isCustomer)
            }
        }
        .padding(.top, topPadding)
    }
}

struct ImageGrid: View {
    let images: [MessageAttachment]
    let isCustomer: Bool
    let onImageTap: (MessageAttachment) -> Void
    let onImageLoaded: () -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        Group {
            if images.count == 1 {
                singleImage
            } else {
                tiledGrid
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var singleImage: some View {
        ImageBubble(attachment: images[0], onTap: onImageTap, onLoaded: onImageLoaded)
            .frame(maxWidth: 260)
    }

    private var tiledGrid: some View {
        let visible = Array(images.prefix(4))
        let overflow = images.count - visible.count
        let indexed: [(offset: Int, element: MessageAttachment)] =
            visible.enumerated().map { ($0.offset, $0.element) }
        let rows: [[(offset: Int, element: MessageAttachment)]] = indexed.chunked(into: 2)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.first!.offset) { row in
                tileRow(row: row, lastVisibleIndex: visible.count - 1, overflow: overflow)
            }
        }
    }

    private func tileRow(
        row: [(offset: Int, element: MessageAttachment)],
        lastVisibleIndex: Int,
        overflow: Int
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(row, id: \.element.url) { item in
                tile(
                    attachment: item.element,
                    showOverflow: item.offset == lastVisibleIndex && overflow > 0,
                    overflow: overflow
                )
            }
        }
    }

    private func tile(
        attachment: MessageAttachment,
        showOverflow: Bool,
        overflow: Int
    ) -> some View {
        ZStack {
            ImageBubble(
                attachment: attachment,
                cropToSquare: true,
                cornerRadius: 4,
                onTap: onImageTap,
                onLoaded: onImageLoaded
            )
            .frame(width: 116, height: 116)
            if showOverflow {
                Color.black.opacity(0.55)
                Text("+\(overflow)")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
        .frame(width: 116, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct ImageBubble: View {
    let attachment: MessageAttachment
    var cropToSquare: Bool = false
    var cornerRadius: CGFloat = 14
    let onTap: (MessageAttachment) -> Void
    let onLoaded: () -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        imageContent
            .frame(
                minWidth: cropToSquare ? nil : 140,
                maxWidth: cropToSquare ? nil : 260,
                minHeight: cropToSquare ? nil : 100,
                maxHeight: cropToSquare ? nil : 360
            )
            .background(colors.receivedBubble)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onTap(attachment) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo: \(attachment.name)")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double-tap to view full screen")
    }

    private var imageContent: some View {
        // CachedAsyncImage hits the SDK's two-tier image cache before
        // falling through to network. Repeated message-list renders
        // (scroll, virtualisation pop) re-render from the in-memory
        // tier with no flicker; second-launch renders hit the disk tier.
        CachedAsyncImage(
            url: URL(string: attachment.url),
            onLoaded: { onLoaded() },
            content: { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: cropToSquare ? .fill : .fit)
            },
            placeholder: { loadingPlaceholder }
        )
    }

    private var loadingPlaceholder: some View {
        ZStack {
            colors.receivedBubble
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: colors.systemMessageText))
        }
        .frame(width: cropToSquare ? 116 : 220, height: cropToSquare ? 116 : 165)
    }

}

struct FileAttachmentRow: View {
    let attachment: MessageAttachment
    let isCustomer: Bool
    @Environment(\.chatColors) private var colors

    private var isPdf: Bool {
        attachment.type.lowercased() == "application/pdf"
            || attachment.name.lowercased().hasSuffix(".pdf")
    }

    private var cardBg: Color {
        isCustomer ? colors.sentBubble : colors.receivedBubble
    }

    private var cardText: Color {
        isCustomer ? colors.sentText : colors.receivedText
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isPdf ? "doc.richtext.fill" : "doc.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(cardText)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ChatColors.mix(cardText, cardBg, 0.16)))
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.footnote.weight(.bold))
                    .foregroundColor(cardText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = MessageRowHelpers.fileDetail(attachment) {
                    Text(verbatim: detail)
                        .font(.caption2)
                        .foregroundColor(cardText.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 260)
        .background(fileShape.fill(cardBg))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: attachment.url) {
                UIApplication.shared.open(url)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isPdf ? "PDF" : "File"): \(attachment.name)" + (attachment.size > 0 ? ", \(MessageRowHelpers.formatBytes(attachment.size))" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to open")
    }

    private var fileShape: RoundedCorners {
        isCustomer
            ? RoundedCorners(tl: 14, tr: 14, bl: 14, br: 6)
            : RoundedCorners(tl: 14, tr: 14, bl: 6, br: 14)
    }
}

// MARK: - Helpers

enum MessageRowHelpers {
    struct Split {
        let images: [MessageAttachment]
        let files: [MessageAttachment]
    }

    static func splitAttachments(_ atts: [MessageAttachment]) -> Split {
        var images: [MessageAttachment] = []
        var files: [MessageAttachment] = []
        for a in atts { isImage(a) ? images.append(a) : files.append(a) }
        return Split(images: images, files: files)
    }

    static func isImage(_ att: MessageAttachment) -> Bool {
        if att.type.lowercased().hasPrefix("image/") { return true }
        let ext = (att.name as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif"].contains(ext)
    }

    static func fileDetail(_ att: MessageAttachment) -> String? {
        let ext = (att.name as NSString).pathExtension.uppercased()
        var parts: [String] = []
        if !ext.isEmpty { parts.append(ext) }
        if att.size > 0 { parts.append(formatBytes(att.size)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return words.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = iso8601.date(from: raw) { return d }
        if let d = iso8601NoFraction.date(from: raw) { return d }
        return nil
    }

    /// Localized short time for a message bubble. Returns nil when no
    /// timestamp is present so the caller can simply omit the row.
    static func formatTimestamp(_ raw: String?) -> String? {
        guard let date = parseDate(raw) else { return nil }
        return timeFormatter.string(from: date)
    }

    /// Stable day-bucket key (yyyy-MM-dd in current calendar) so the
    /// message list can detect day boundaries without comparing Dates
    /// directly.
    static func dayKey(_ raw: String?) -> String? {
        guard let date = parseDate(raw) else { return nil }
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Human-readable day separator label. Today / Yesterday / localized
    /// medium date. Matches the Android `MessageList` day-header rule.
    static func dayLabel(_ raw: String?) -> String? {
        guard let date = parseDate(raw) else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }
}

/// Centered date chip rendered between messages on different days.
struct DaySeparator: View {
    let label: String
    @Environment(\.chatColors) private var colors

    var body: some View {
        HStack {
            Spacer()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(colors.daySeparatorText)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(colors.daySeparatorBg))
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Messages from \(label)")
    }
}

extension Array {
    /// Splits the array into rows of size `n`. Tail row may be shorter.
    /// Used by ``ImageGrid`` to pack a 2-column tile grid without
    /// dropping the trailing odd image.
    func chunked(into n: Int) -> [[Element]] {
        guard n > 0 else { return [] }
        return stride(from: 0, to: count, by: n).map {
            Array(self[$0..<Swift.min($0 + n, count)])
        }
    }
}

#endif
