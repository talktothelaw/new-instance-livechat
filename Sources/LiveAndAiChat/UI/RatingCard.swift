import Foundation

enum RatingCopy {
    static let placeholder = "Tell us more (optional)"
    static let send = "Send"
    static let skip = "Skip"
    static let thanks = "Thanks for your feedback."
    static let failure = "Could not send your rating. Try again."

    static func title(agentName: String?) -> String {
        guard let name = agentName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "How was your chat?"
        }
        return "How was your chat with \(name)?"
    }

    static func starLabel(_ score: Int) -> String {
        score == 1 ? "1 star" : "\(score) stars"
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

struct RatingCard: View {
    let rating: PendingRating
    let onSubmit: (Int, String?) -> Void
    let onSkip: () -> Void
    @Environment(\.chatColors) private var colors
    @State private var score = 0
    @State private var comment = ""

    private var busy: Bool { rating.status == .sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if rating.status == .sent {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(colors.successColor)
                        .accessibilityHidden(true)
                    Text(verbatim: RatingCopy.thanks)
                        .foregroundColor(colors.receivedText)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
                .onAppear { UIAccessibility.post(notification: .announcement, argument: RatingCopy.thanks) }
            } else {
                Text(verbatim: RatingCopy.title(agentName: rating.agentName))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(colors.receivedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            score = value
                        } label: {
                            Image(systemName: value <= score ? "star.fill" : "star")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(value <= score ? colors.warningColor : colors.systemMessageText)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(value == score ? colors.warnTint : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel(RatingCopy.starLabel(value))
                        .accessibilityAddTraits(value == score ? .isSelected : [])
                    }
                }
                if score > 0 {
                    TextField(RatingCopy.placeholder, text: $comment)
                        .font(.callout)
                        .foregroundColor(colors.inputText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.inputBg))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.inputBorder, lineWidth: 1))
                        .disabled(busy)
                        .onChange(of: comment) { value in
                            if value.count > ChatStore.maxRatingComment {
                                comment = String(value.prefix(ChatStore.maxRatingComment))
                            }
                        }
                }
                if rating.status == .error {
                    Text(verbatim: RatingCopy.failure)
                        .font(.caption)
                        .foregroundColor(colors.errorColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .onAppear { UIAccessibility.post(notification: .announcement, argument: RatingCopy.failure) }
                }
                HStack(spacing: 8) {
                    if score > 0 {
                        Button {
                            onSubmit(score, comment)
                        } label: {
                            Text(verbatim: RatingCopy.send)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(colors.sendButtonIcon)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.sendButtonBg))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .opacity(busy ? 0.6 : 1)
                    }
                    Button(action: onSkip) {
                        Text(verbatim: RatingCopy.skip)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(colors.systemMessageText)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.background)
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(colors.background)
        .accessibilityElement(children: .contain)
    }
}
#endif
