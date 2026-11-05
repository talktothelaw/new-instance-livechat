import Foundation

struct ElicitationChoice: Equatable {
    let value: String
    let label: String
}

struct ElicitationField: Equatable {
    enum Kind: Equatable {
        case text
        case choice([ElicitationChoice])
        case number(integer: Bool)
        case toggle
    }

    let key: String
    let label: String
    let helper: String?
    let kind: Kind
    let required: Bool
    let initialText: String
    let initialOn: Bool
}

enum ElicitationForm {
    static let requiredError = "This field is required."
    static let integerError = "Enter a whole number."
    static let numberError = "Enter a number."
    static let answerError = "Could not send your answer. Try again."

    static func fields(from schema: ElicitationValue?) -> [ElicitationField] {
        guard case .object(let root)? = schema, case .object(let properties)? = root["properties"] else { return [] }
        var required: Set<String> = []
        if case .array(let names)? = root["required"] { required = Set(names.compactMap(\.text)) }
        return properties.keys.sorted().compactMap { key -> ElicitationField? in
            guard case .object(let def)? = properties[key], case .string(let type)? = def["type"] else { return nil }
            let options = choices(def)
            let kind: ElicitationField.Kind
            switch type {
            case "string": kind = options.isEmpty ? .text : .choice(options)
            case "number", "integer": kind = .number(integer: type == "integer")
            case "boolean": kind = .toggle
            default: return nil
            }
            var label = key
            if case .string(let title)? = def["title"], !title.isEmpty { label = title }
            var helper: String?
            if case .string(let text)? = def["description"], !text.isEmpty { helper = text }
            return ElicitationField(
                key: key,
                label: label,
                helper: helper,
                kind: kind,
                required: required.contains(key),
                initialText: kind == .toggle ? "" : def["default"]?.text ?? "",
                initialOn: def["default"] == .bool(true)
            )
        }
    }

    static func canSend(_ schema: ElicitationValue?) -> Bool {
        guard case .object(let root)? = schema, case .array(let names)? = root["required"] else { return true }
        let shown = Set(fields(from: schema).map(\.key))
        return names.allSatisfy { $0.text.map(shown.contains) ?? false }
    }

    private static func choices(_ def: [String: ElicitationValue]) -> [ElicitationChoice] {
        if case .array(let options)? = def["oneOf"] {
            return options.compactMap { option in
                guard case .object(let entry) = option, let value = entry["const"]?.text else { return nil }
                return ElicitationChoice(value: value, label: nonEmpty(entry["title"]?.text) ?? value)
            }
        }
        guard case .array(let values)? = def["enum"] else { return [] }
        var names: [ElicitationValue?] = Array(repeating: nil, count: values.count)
        if case .array(let given)? = def["enumNames"], given.count == values.count { names = given }
        return zip(values, names).compactMap { raw, name in
            raw.text.map { ElicitationChoice(value: $0, label: nonEmpty(name?.text) ?? $0) }
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        text?.isEmpty == false ? text : nil
    }

    static func answer(
        _ fields: [ElicitationField],
        texts: [String: String],
        toggles: [String: Bool],
        locale: Locale = .current
    ) -> (content: [String: ElicitationValue], problems: [String: String]) {
        let decimal = NumberFormatter()
        decimal.locale = locale
        decimal.numberStyle = .decimal
        decimal.usesGroupingSeparator = false
        var content: [String: ElicitationValue] = [:]
        var problems: [String: String] = [:]
        for field in fields {
            if field.kind == .toggle {
                content[field.key] = .bool(toggles[field.key] ?? field.initialOn)
                continue
            }
            let text = (texts[field.key] ?? field.initialText).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                if field.required { problems[field.key] = requiredError }
            } else if case .number(let integer) = field.kind {
                if let number = decimal.number(from: text)?.doubleValue ?? Double(text),
                   number.isFinite, !integer || number.rounded() == number {
                    content[field.key] = .number(number)
                } else {
                    problems[field.key] = integer ? integerError : numberError
                }
            } else {
                content[field.key] = .string(text)
            }
        }
        return (content, problems)
    }

    static func statusLine(_ status: ElicitationStatus) -> String? {
        switch status {
        case .pending: return nil
        case .answered: return "Sent"
        case .declined: return "Declined"
        case .cancelled: return "Cancelled"
        case .expired: return "This step expired"
        case .completed: return "Done"
        }
    }

    static func secureUrl(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    static func reopenUrl(_ step: Elicitation) -> URL? {
        step.mode == .url && step.status == .answered ? secureUrl(step.url) : nil
    }

    static func hostLabel(_ url: URL) -> String {
        (url.host ?? "") + (url.port.flatMap { $0 == 443 ? nil : ":\($0)" } ?? "")
    }
}

#if canImport(UIKit)
import SwiftUI

struct ElicitationCard: View {
    let prompt: String
    let elicitation: Elicitation
    let onAnswer: (ElicitationAction, [String: ElicitationValue]?) async throws -> Void
    let onOpen: (URL) -> Bool
    @Environment(\.chatColors) private var colors

    var body: some View {
        if let line = ElicitationForm.statusLine(elicitation.status) {
            VStack(alignment: .leading, spacing: 12) {
                StepPrompt(text: prompt)
                StepStatus(text: line, done: elicitation.status == .answered || elicitation.status == .completed)
                if let url = ElicitationForm.reopenUrl(elicitation) {
                    StepButton(title: "Open secure page", icon: "arrow.up.right.square", primary: true) { _ = onOpen(url) }
                }
            }
        } else {
            PendingStep(prompt: prompt, elicitation: elicitation, onAnswer: onAnswer, onOpen: onOpen)
                .id(elicitation.id)
        }
    }
}

private struct PendingStep: View {
    let prompt: String
    let elicitation: Elicitation
    let onAnswer: (ElicitationAction, [String: ElicitationValue]?) async throws -> Void
    let onOpen: (URL) -> Bool
    @Environment(\.chatColors) private var colors
    @State private var texts: [String: String] = [:]
    @State private var toggles: [String: Bool] = [:]
    @State private var problems: [String: String] = [:]
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        let isForm = elicitation.mode == .form
        let sendable = isForm && ElicitationForm.canSend(elicitation.requestedSchema)
        let fields = sendable ? ElicitationForm.fields(from: elicitation.requestedSchema) : []
        let url = isForm ? nil : ElicitationForm.secureUrl(elicitation.url)

        VStack(alignment: .leading, spacing: 14) {
            StepPrompt(text: prompt)
            if let url {
                Text(verbatim: "You will finish this step on \(ElicitationForm.hostLabel(url)).")
                    .font(.footnote)
                    .foregroundColor(colors.systemMessageText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(fields, id: \.key) { field in
                fieldView(field)
            }
            if failed {
                Text(verbatim: ElicitationForm.answerError)
                    .font(.footnote)
                    .foregroundColor(colors.errorColor)
            }
            HStack(spacing: 8) {
                if sendable {
                    StepButton(title: "Send", primary: true, busy: busy) { send(fields) }
                } else if let url {
                    StepButton(title: "Open secure page", icon: "arrow.up.right.square", primary: true, busy: busy) { open(url) }
                }
                StepButton(title: "Not now", primary: false, busy: busy) { submit(.decline, nil) }
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: ElicitationField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch field.kind {
            case .toggle:
                Toggle(isOn: Binding(
                    get: { toggles[field.key] ?? field.initialOn },
                    set: { toggles[field.key] = $0 }
                )) {
                    Text(verbatim: field.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(colors.receivedText)
                }
                .toggleStyle(SwitchToggleStyle(tint: colors.sendButtonBg))
                .frame(minHeight: 44)
            case .choice(let options):
                label(field)
                Menu {
                    Button("Choose one") { texts[field.key] = "" }
                    ForEach(options, id: \.value) { option in
                        Button(option.label) { texts[field.key] = option.value }
                    }
                } label: {
                    HStack {
                        Text(verbatim: choiceLabel(text(field), in: options))
                            .foregroundColor(colors.inputText)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(colors.inputPlaceholder)
                    }
                    .font(.callout)
                    .modifier(InputFrame(colors: colors))
                }
                .accessibilityLabel(Text(verbatim: field.label))
            case .text, .number:
                label(field)
                TextField("", text: Binding(
                    get: { text(field) },
                    set: { texts[field.key] = $0 }
                ))
                .font(.callout)
                .foregroundColor(colors.inputText)
                .keyboardType(field.kind == .text ? .default : .numbersAndPunctuation)
                .modifier(InputFrame(colors: colors))
                .accessibilityLabel(Text(verbatim: field.label))
            }
            if let helper = field.helper {
                Text(verbatim: helper)
                    .font(.caption)
                    .foregroundColor(colors.systemMessageText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = problems[field.key] {
                Text(verbatim: problem)
                    .font(.caption)
                    .foregroundColor(colors.errorColor)
            }
        }
    }

    private func label(_ field: ElicitationField) -> some View {
        Text(verbatim: field.label)
            .font(.footnote.weight(.semibold))
            .foregroundColor(colors.receivedText)
            .accessibilityHidden(true)
    }

    private func text(_ field: ElicitationField) -> String {
        texts[field.key] ?? field.initialText
    }

    private func choiceLabel(_ value: String, in options: [ElicitationChoice]) -> String {
        if value.isEmpty { return "Choose one" }
        return options.first { $0.value == value }?.label ?? value
    }

    private func send(_ fields: [ElicitationField]) {
        guard !busy else { return }
        let result = ElicitationForm.answer(fields, texts: texts, toggles: toggles)
        problems = result.problems
        guard result.problems.isEmpty else { return }
        submit(.accept, result.content)
    }

    private func open(_ url: URL) {
        guard !busy else { return }
        failed = false
        guard onOpen(url) else {
            failed = true
            return
        }
        submit(.accept, nil)
    }

    private func submit(_ action: ElicitationAction, _ content: [String: ElicitationValue]?) {
        guard !busy else { return }
        busy = true
        failed = false
        Task {
            do {
                try await onAnswer(action, content)
            } catch {
                busy = false
                failed = true
            }
        }
    }
}

private struct StepPrompt: View {
    let text: String
    @Environment(\.chatColors) private var colors

    var body: some View {
        if !text.isEmpty {
            Text(verbatim: text)
                .font(.callout.weight(.bold))
                .foregroundColor(colors.receivedText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

private struct StepStatus: View {
    let text: String
    let done: Bool
    @Environment(\.chatColors) private var colors

    var body: some View {
        HStack(spacing: 4) {
            if done {
                Image(systemName: "checkmark")
                    .foregroundColor(colors.successColor)
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .foregroundColor(colors.receivedText)
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
        .background(Capsule().fill(done ? colors.successTint : colors.receivedBubble))
    }
}

private struct StepButton: View {
    let title: String
    var icon: String?
    let primary: Bool
    var busy = false
    let action: () -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: title)
                if let icon { Image(systemName: icon) }
            }
            .font(.callout.weight(primary ? .bold : .semibold))
            .foregroundColor(primary ? colors.sendButtonIcon : colors.receivedText)
            .padding(.horizontal, 18)
            .frame(maxWidth: primary ? .infinity : nil, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(primary ? colors.sendButtonBg : colors.receivedBubble)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
    }
}

private struct InputFrame: ViewModifier {
    let colors: ChatColors

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.inputBg))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.inputBorder, lineWidth: 1))
    }
}

#endif
