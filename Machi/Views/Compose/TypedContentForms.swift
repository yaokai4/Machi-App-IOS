import SwiftUI
import UIKit

// MARK: - Shared form primitives
//
// The original TypedContentForms.swift held one giant file with every
// per-type form. It has now been split: each ContentType lives in its
// own file under `Views/Compose/Forms/<Type>FormView.swift` for fast
// editor open + smaller diffs, and this file keeps the building
// blocks they all reuse (section card, labeled text field, chip
// choice row).

struct TypedFormSection<Content: View>: View {
    @Environment(\.appLanguage) private var language
    let titleKey: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L(titleKey, language), systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            content
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

struct TypedTextField: View {
    @Environment(\.appLanguage) private var language
    let titleKey: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal
    /// When true the field is rendered with a small accent dot to
    /// communicate "required" in the form. Pure visual hint — the
    /// actual gating happens in `ComposePostViewModel.canPublish`.
    var isRequired: Bool = false

    init(
        _ titleKey: String,
        text: Binding<String>,
        placeholder: String = "",
        keyboard: UIKeyboardType = .default,
        axis: Axis = .horizontal,
        isRequired: Bool = false
    ) {
        self.titleKey = titleKey
        self._text = text
        self.placeholder = placeholder
        self.keyboard = keyboard
        self.axis = axis
        self.isRequired = isRequired
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(L(titleKey, language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isRequired {
                    Text("*")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
            TextField(placeholder.isEmpty ? L(titleKey, language) : placeholder, text: $text, axis: axis)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline.weight(.semibold))
                .lineLimit(axis == .vertical ? 6 : 1)
                .padding(.horizontal, 12)
                .frame(minHeight: axis == .vertical ? 72 : 40)
                .kxGlassSurface(radius: KXRadius.md)
        }
    }
}

struct TypedChoiceRow: View {
    @Environment(\.appLanguage) private var language
    let titleKey: String
    @Binding var selection: String
    let options: [(value: String, labelKey: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(titleKey, language))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection = option.value
                    } label: {
                        Text(L(option.labelKey, language))
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .kxGlassCapsule(isSelected: selection == option.value)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == option.value ? KXColor.accent : .primary)
                }
            }
        }
    }
}

// MARK: - Seed helper

extension ComposePostViewModel {
    /// Seed a default string attribute if the user hasn't touched
    /// the field yet. Used by typed forms to set "available" /
    /// "JPY" / "part_time" etc. on first appearance.
    func seedDefaultAttribute(_ key: String, _ value: String) {
        if attributes[key] == nil {
            setStringAttribute(key, value)
        }
    }
}
