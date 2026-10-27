import Foundation

struct ElicitationField: Equatable {
    enum Kind: Equatable {
        case text
        case choice([String])
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

    static func fields(from schema: JSONValue?) -> [ElicitationField] {
        guard case .object(let root)? = schema, case .object(let properties)? = root["properties"] else { return [] }
        var required: Set<String> = []
        if case .array(let names)? = root["required"] { required = Set(names.compactMap(\.text)) }
        return properties.keys.sorted().compactMap { key -> ElicitationField? in
            guard case .object(let def)? = properties[key], case .string(let type)? = def["type"] else { return nil }
            var options: [String] = []
            if case .array(let values)? = def["enum"] { options = values.compactMap(\.text) }
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

    static func answer(
        _ fields: [ElicitationField],
        texts: [String: String],
        toggles: [String: Bool],
        locale: Locale = .current
    ) -> (content: [String: JSONValue], problems: [String: String]) {
        let decimal = NumberFormatter()
        decimal.locale = locale
        decimal.numberStyle = .decimal
        decimal.usesGroupingSeparator = false
        var content: [String: JSONValue] = [:]
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

    static func hostLabel(_ url: URL) -> String {
        (url.host ?? "") + (url.port.map { ":\($0)" } ?? "")
    }
}

#if canImport(UIKit)
import SwiftUI

struct ElicitationCard: View {
    let prompt: String
    let elicitation: Elicitation
    let onAnswer: (ElicitationAction, [String: JSONValue]?) async throws -> Void
    let onOpen: (URL) -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        if let line = ElicitationForm.statusLine(elicitation.status) {
            Text(verbatim: line)
                .font(.caption.weight(.medium))
                .foregroundColor(colors.receivedTimestamp)
        } else {
            PendingStep(prompt: prompt, elicitation: elicitation, onAnswer: onAnswer, onOpen: onOpen)
                .id(elicitation.id)
        }
    }
}

private struct PendingStep: View {
    let prompt: String
    let elicitation: Elicitation
    let onAnswer: (ElicitationAction, [String: JSONValue]?) async throws -> Void
    let onOpen: (URL) -> Void
    @Environment(\.chatColors) private var colors
    @State private var texts: [String: String] = [:]
    @State private var toggles: [String: Bool] = [:]
    @State private var problems: [String: String] = [:]
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        let isForm = elicitation.mode == .form
        let fields = isForm ? ElicitationForm.fields(from: elicitation.requestedSchema) : []
        let url = isForm ? nil : ElicitationForm.secureUrl(elicitation.url)

        VStack(alignment: .leading, spacing: 12) {
            if !prompt.isEmpty {
                Text(verbatim: prompt)
                    .font(.body)
                    .foregroundColor(colors.receivedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url {
                Text(verbatim: "You will finish this step on \(ElicitationForm.hostLabel(url)).")
                    .font(.caption)
                    .foregroundColor(colors.receivedTimestamp)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(fields, id: \.key) { field in
                fieldView(field)
            }
            if failed {
                Text(verbatim: ElicitationForm.answerError)
                    .font(.caption)
                    .foregroundColor(colors.errorColor)
            }
            HStack(spacing: 8) {
                if isForm {
                    actionButton("Send", primary: true) { send(fields) }
                } else if let url {
                    actionButton("Open secure page", icon: "arrow.up.right.square", primary: true) { open(url) }
                }
                actionButton("Not now", primary: false) { submit(.decline, nil) }
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: ElicitationField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch field.kind {
            case .toggle:
                Toggle(isOn: Binding(
                    get: { toggles[field.key] ?? field.initialOn },
                    set: { toggles[field.key] = $0 }
                )) {
                    Text(verbatim: field.label)
                        .font(.caption.weight(.medium))
                        .foregroundColor(colors.receivedText)
                }
                .toggleStyle(SwitchToggleStyle(tint: colors.primary))
            case .choice(let options):
                label(field)
                Menu {
                    Button("Choose one") { texts[field.key] = "" }
                    ForEach(options, id: \.self) { option in
                        Button(option) { texts[field.key] = option }
                    }
                } label: {
                    HStack {
                        Text(verbatim: text(field).isEmpty ? "Choose one" : text(field))
                            .foregroundColor(colors.inputText)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(colors.inputPlaceholder)
                    }
                    .font(.subheadline)
                    .modifier(InputFrame(colors: colors))
                }
                .accessibilityLabel(Text(verbatim: field.label))
            case .text, .number:
                label(field)
                TextField("", text: Binding(
                    get: { text(field) },
                    set: { texts[field.key] = $0 }
                ))
                .font(.subheadline)
                .foregroundColor(colors.inputText)
                .keyboardType(field.kind == .text ? .default : .numbersAndPunctuation)
                .modifier(InputFrame(colors: colors))
                .accessibilityLabel(Text(verbatim: field.label))
            }
            if let helper = field.helper {
                Text(verbatim: helper)
                    .font(.caption)
                    .foregroundColor(colors.receivedTimestamp)
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
            .font(.caption.weight(.medium))
            .foregroundColor(colors.receivedText)
            .accessibilityHidden(true)
    }

    private func text(_ field: ElicitationField) -> String {
        texts[field.key] ?? field.initialText
    }

    private func actionButton(_ title: String, icon: String? = nil, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(verbatim: title)
            }
            .font(.footnote.weight(.medium))
            .foregroundColor(primary ? colors.sendButtonIcon : colors.receivedText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(primary ? colors.sendButtonBg : colors.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(primary ? Color.clear : colors.inputBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
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
        onOpen(url)
        submit(.accept, nil)
    }

    private func submit(_ action: ElicitationAction, _ content: [String: JSONValue]?) {
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

private struct InputFrame: ViewModifier {
    let colors: ChatColors

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(colors.inputBg))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.inputBorder, lineWidth: 1))
    }
}

#endif
