#if canImport(UIKit)
import SwiftUI
import UIKit

/// Text input + attachment chip strip + send button. Mirrors the Android
/// `Composer` Composable and the web SDK's `Composer.tsx`.
///
/// Behaviour:
///   - Send is disabled while text + attachments are both empty.
///   - Pressing send clears the text field; the parent is responsible for
///     draining and clearing the attachment queue.
///   - Typing debounce: emits `onTyping(true)` on the first keystroke,
///     `onTyping(false)` after 4s of silence. This matches the typing
///     timeouts used by the Android composer.
struct Composer: View {
    let placeholderText: String
    let pendingAttachments: [QueuedAttachment]
    let attachmentsAllowed: Bool
    let enabled: Bool
    let onPickFile: () -> Void
    let onRemoveAttachment: (String) -> Void
    let onRetryAttachment: (String) -> Void
    let onSend: (String) -> Void
    let onTyping: (Bool) -> Void
    @Binding var text: String

    @State private var isTyping: Bool = false
    @State private var typingDebounce: DispatchWorkItem?
    @Environment(\.chatColors) private var colors

    private var canSend: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUploaded = pendingAttachments.contains { $0.status == .uploaded }
        return enabled && !isUploading && (!trimmed.isEmpty || hasUploaded)
    }

    /// Send is held while any attachment is still mid-flight. Matches the
    /// Android composer's behaviour — we don't want the customer to send
    /// a message that references a URL that hasn't been minted yet.
    private var isUploading: Bool {
        pendingAttachments.contains { $0.status == .uploading || $0.status == .queued }
    }

    var body: some View {
        VStack(spacing: 8) {
            if !pendingAttachments.isEmpty {
                AttachmentChipStrip(
                    items: pendingAttachments,
                    onRemove: onRemoveAttachment,
                    onRetry: onRetryAttachment
                )
            }
            HStack(alignment: .bottom, spacing: 2) {
                if attachmentsAllowed {
                    Button(action: onPickFile) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(colors.attachmentButton)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .accessibilityLabel("Attach file")
                    .accessibilityHint("Opens a chooser for a photo or document to attach")
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholderText)
                            .foregroundColor(colors.inputPlaceholder)
                            .font(.callout)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.callout)
                        .foregroundColor(colors.inputText)
                        .padding(.top, 4)
                        .scrollContentBackgroundHiddenIfAvailable()
                        .background(Color.clear)
                        .onChange(of: text) { newValue in
                            handleTextChange(newValue)
                        }
                }
                .frame(height: composerInputHeight)
                .padding(.leading, attachmentsAllowed ? 0 : 10)

                Button(action: sendTapped) {
                    Group {
                        if isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: colors.sendButtonIcon))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(colors.sendButtonIcon)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(colors.sendButtonBg))
                    .opacity(canSend ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(isUploading ? "Uploading" : "Send")
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(colors.inputBg))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(colors.inputBorder, lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        // Only ignore the container safe area (home-indicator gutter)
        // — NOT the keyboard. Plain `.ignoresSafeArea(edges: .bottom)`
        // can swallow the keyboard inset on some iOS versions, leaving
        // a white strip where the composer ends up jammed against the
        // keyboard. `.container` confines the extension to the system
        // chrome only, so the composer auto-avoids the keyboard
        // cleanly.
        .background(colors.footerContainer.ignoresSafeArea(.container, edges: .bottom))
        .overlay(Rectangle().fill(colors.hairline).frame(height: 1), alignment: .top)
    }

    /// Compose-time height for the input rounded rect. Matches the web's
    /// `min-h-[36px] max-h-[120px]` semantics — we approximate line count
    /// via newline characters since TextEditor doesn't expose intrinsic
    /// content size. Single-line by default; grows up to ~5 lines then
    /// scrolls internally.
    private var composerInputHeight: CGFloat {
        let newlineCount = text.reduce(into: 0) { $0 += $1 == "\n" ? 1 : 0 }
        // 44 = single line; grow ~21pt per newline up to 120.
        let raw = 44 + CGFloat(newlineCount) * 21
        return min(max(raw, 44), 120)
    }

    private func handleTextChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !isTyping {
            isTyping = true
            onTyping(true)
        }
        typingDebounce?.cancel()
        let work = DispatchWorkItem {
            if isTyping {
                isTyping = false
                onTyping(false)
            }
        }
        typingDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func sendTapped() {
        guard canSend else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSend(body)
        text = ""
        if isTyping {
            isTyping = false
            onTyping(false)
        }
        typingDebounce?.cancel()
    }
}

/// Horizontally scrolling row of upload chips, one per queued
/// attachment. Hidden scrollbar; native swipe scroll.
struct AttachmentChipStrip: View {
    let items: [QueuedAttachment]
    let onRemove: (String) -> Void
    let onRetry: (String) -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(items) { item in
                    AttachmentChip(item: item, onRemove: onRemove, onRetry: onRetry)
                }
            }
        }
    }
}

struct AttachmentChip: View {
    let item: QueuedAttachment
    let onRemove: (String) -> Void
    let onRetry: (String) -> Void
    @Environment(\.chatColors) private var colors

    private var inFlight: Bool { item.status == .uploading || item.status == .queued }
    private var failed: Bool { item.status == .failed }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                colors.background
                if failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.errorColor)
                } else {
                    content
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(failed ? colors.errorColor : colors.receivedText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if inFlight {
                        ZStack(alignment: .leading) {
                            Capsule().fill(colors.hairline)
                            Capsule()
                                .fill(colors.sendButtonBg)
                                .frame(width: 40 * CGFloat(progressFraction))
                        }
                        .frame(width: 40, height: 4)
                        .accessibilityHidden(true)
                    }
                    Text(subline)
                        .font(.caption2)
                        .foregroundColor(colors.systemMessageText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 140, alignment: .leading)
            if failed {
                Button { onRetry(item.id) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colors.errorColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry")
            }
            if !inFlight {
                Button { onRemove(item.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(colors.systemMessageText)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove attachment")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, inFlight ? 10 : 2)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(failed ? colors.errorTint : colors.receivedBubble))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(failed ? colors.errorColor : colors.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if isImageAttachment {
            if let preview = previewImage {
                preview
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                    .foregroundColor(colors.systemMessageText)
            }
        } else {
            Image(systemName: "doc.fill")
                .font(.system(size: 13))
                .foregroundColor(colors.systemMessageText)
        }
    }

    private var isImageAttachment: Bool {
        if item.mimeType.lowercased().hasPrefix("image/") { return true }
        let ext = (item.name as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif", "heic"].contains(ext)
    }

    private var progressFraction: Double {
        item.status == .queued ? 0 : max(0, min(1, item.progress))
    }

    private var displayName: String {
        let max = 12
        if item.name.count <= max { return item.name }
        let ns = item.name as NSString
        let ext = ns.pathExtension
        if !ext.isEmpty {
            let base = (item.name as NSString).deletingPathExtension
            let suffix = "." + ext
            let available = max - suffix.count - 1
            if available > 2 {
                let endIdx = base.index(base.startIndex, offsetBy: min(available, base.count))
                return String(base[..<endIdx]) + "…" + suffix
            }
        }
        let endIdx = item.name.index(item.name.startIndex, offsetBy: max - 1)
        return String(item.name[..<endIdx]) + "…"
    }

    private var subline: String {
        switch item.status {
        case .queued: return "Queued"
        case .uploading: return "\(Int(item.progress * 100))%"
        case .uploaded: return MessageRowHelpers.formatBytes(item.size)
        case .failed: return item.errorReason ?? "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var previewImage: AnyView? {
        let primary = item.previewUri.flatMap { URL(string: $0) }
        let fallback = item.publicUrl.flatMap { URL(string: $0) }
        guard let url = primary ?? fallback else { return nil }

        if url.isFileURL,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            return AnyView(
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
        }

        // Remote preview (post-upload) — goes through the cached image
        // loader so the chip thumbnail doesn't re-fetch every render.
        return AnyView(
            CachedAsyncImage(
                url: url,
                content: { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                },
                placeholder: { Color.clear }
            )
        )
    }
}

// MARK: - iOS-15 niceties

private extension View {
    /// Hides the default TextEditor background on iOS 16+ so the editor
    /// transparently sits inside our rounded container. No-op on iOS 14/15
    /// — the SwiftUI default already paints white there.
    @ViewBuilder
    func scrollContentBackgroundHiddenIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

#endif
