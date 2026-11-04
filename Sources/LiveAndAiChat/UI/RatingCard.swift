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
        VStack(alignment: .leading, spacing: 12) {
            if rating.status == .sent {
                Text(verbatim: RatingCopy.thanks)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
                    .onAppear { UIAccessibility.post(notification: .announcement, argument: RatingCopy.thanks) }
            } else {
                Text(verbatim: RatingCopy.title(agentName: rating.agentName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            score = value
                        } label: {
                            Image(systemName: value <= score ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundColor(value <= score ? colors.sendButtonBg : colors.textSecondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel(RatingCopy.starLabel(value))
                        .accessibilityAddTraits(value == score ? .isSelected : [])
                    }
                }
                if score > 0 {
                    TextField(RatingCopy.placeholder, text: $comment)
                        .font(.subheadline)
                        .foregroundColor(colors.inputText)
                        .padding(10)
                        .background(colors.inputBg)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.inputBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                HStack(spacing: 10) {
                    if score > 0 {
                        Button {
                            onSubmit(score, comment)
                        } label: {
                            Text(verbatim: RatingCopy.send)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(colors.sendButtonIcon)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 44)
                                .background(colors.sendButtonBg)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                    Button(action: onSkip) {
                        Text(verbatim: RatingCopy.skip)
                            .font(.subheadline)
                            .foregroundColor(colors.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.footerContainer)
        .overlay(alignment: .top) { Rectangle().fill(colors.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}
#endif
