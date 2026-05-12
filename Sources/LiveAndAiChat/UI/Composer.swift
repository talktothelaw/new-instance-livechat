#if canImport(UIKit)
import SwiftUI

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
    let onSend: (String) -> Void
    let onTyping: (Bool) -> Void

    @State private var text: String = ""
    @State private var isTyping: Bool = false
    @State private var typingDebounce: DispatchWorkItem?
    @Environment(\.chatColors) private var colors

    private var canSend: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUploaded = pendingAttachments.contains { $0.status == .uploaded }
        return enabled && (!trimmed.isEmpty || hasUploaded)
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(colors.border)
            if !pendingAttachments.isEmpty {
                AttachmentChipStrip(
                    items: pendingAttachments,
                    onRemove: onRemoveAttachment
                )
                .environment(\.chatColors, colors)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if attachmentsAllowed {
                    Button(action: onPickFile) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18))
                            .foregroundColor(colors.attachmentButton)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                }
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholderText)
                            .foregroundColor(colors.inputPlaceholder)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .foregroundColor(colors.inputText)
                        .frame(minHeight: 36, maxHeight: 120)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .scrollContentBackgroundHiddenIfAvailable()
                        .background(Color.clear)
                        .onChange(of: text) { newValue in
                            handleTextChange(newValue)
                        }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(colors.inputBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colors.inputBorder, lineWidth: 1)
                )

                Button(action: sendTapped) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.sendButtonIcon)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(canSend ? colors.sendButtonBg : colors.sendButtonBg.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(colors.footerContainer)
        }
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

/// Horizontally scrolling row of chips, one per queued attachment. Each
/// chip shows file name, status (uploading %, uploaded, failed) and a
/// remove button.
struct AttachmentChipStrip: View {
    let items: [QueuedAttachment]
    let onRemove: (String) -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    AttachmentChip(item: item, onRemove: onRemove)
                        .environment(\.chatColors, colors)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(colors.footerContainer)
    }
}

struct AttachmentChip: View {
    let item: QueuedAttachment
    let onRemove: (String) -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.text)
                    .lineLimit(1)
                Text(subline)
                    .font(.system(size: 10))
                    .foregroundColor(colors.textSecondary)
            }
            .frame(maxWidth: 140, alignment: .leading)
            Button { onRemove(item.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(colors.typingBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .uploading, .queued:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        case .uploaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(colors.successColor)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(colors.errorColor)
        }
    }

    private var subline: String {
        switch item.status {
        case .queued: return "Queued"
        case .uploading: return "\(Int(item.progress * 100))%"
        case .uploaded: return "Uploaded"
        case .failed: return item.errorReason ?? "Failed"
        }
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
