import SwiftUI

struct WebsiteArgumentsSettingsView: View {
    let isRunning: Bool

    @State private var rules = WebsiteArgumentRules.load()
    @State private var editingRule: WebsiteArgumentRule?
    @State private var testLink = ""

    var body: some View {
        Form {
            Section {
                if rules.isEmpty {
                    Text("settings.website_args.empty")
                        .foregroundStyle(.secondary)
                }

                ForEach(rules) { rule in
                    Button {
                        editingRule = rule
                    } label: {
                        ruleRow(for: rule)
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    rules.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    rules.move(fromOffsets: source, toOffset: destination)
                }

                Button {
                    editingRule = WebsiteArgumentRule()
                } label: {
                    Label("settings.website_args.add", systemImage: "plus")
                }
            } header: {
                Text("settings.website_args.rules.section")
            } footer: {
                Text("settings.website_args.priority.footer")
            }

            Section("settings.website_args.test.section") {
                TextField("settings.website_args.test.placeholder", text: $testLink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !testLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    testResult
                }
            }
        }
        .disabled(isRunning)
        .toolbar {
            if !rules.isEmpty {
                EditButton()
                    .disabled(isRunning)
            }
        }
        .sheet(item: $editingRule) { rule in
            WebsiteArgumentRuleEditorView(
                rule: rule,
                isNew: !rules.contains { $0.id == rule.id },
                onSave: saveRule
            )
        }
        .onChange(of: rules) { _, newRules in
            WebsiteArgumentRules.save(newRules)
        }
        .navigationTitle("settings.website_args.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ruleRow(for rule: WebsiteArgumentRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: rule.pattern)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if rule.matchType == .regex {
                    badge("settings.website_args.match_type.regex", color: .purple)
                }
                if !rule.isEnabled {
                    badge("settings.website_args.disabled_badge", color: .gray)
                }
            }

            Text(verbatim: rule.trimmedArguments)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .opacity(rule.isEnabled ? 1 : 0.6)
        .padding(.vertical, 2)
    }

    private func badge(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private var testResult: some View {
        if let rule = WebsiteArgumentRules.matchingRule(for: testLink, in: rules) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(
                        String(
                            format: String(localized: "settings.website_args.test.match", bundle: .app),
                            rule.pattern
                        )
                    )
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Text(verbatim: rule.trimmedArguments)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("settings.website_args.test.no_match", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func saveRule(_ rule: WebsiteArgumentRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }
}

private struct WebsiteArgumentRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: WebsiteArgumentRule
    let isNew: Bool
    let onSave: (WebsiteArgumentRule) -> Void

    private var hasPattern: Bool {
        !rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        rule.isValid && !rule.trimmedArguments.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("settings.website_args.match_type", selection: $rule.matchType) {
                        Text("settings.website_args.match_type.website")
                            .tag(WebsiteArgumentMatchType.website)
                        Text("settings.website_args.match_type.regex")
                            .tag(WebsiteArgumentMatchType.regex)
                    }
                    .pickerStyle(.segmented)

                    TextField(patternPlaceholder, text: $rule.pattern)
                        .keyboardType(rule.matchType == .website ? .URL : .asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                    if hasPattern, !rule.isValid {
                        Label(patternError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text(patternHelp)
                }

                Section {
                    TextField(
                        "settings.website_args.arguments.placeholder",
                        text: $rule.arguments,
                        axis: .vertical
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("settings.website_args.arguments.title")
                } footer: {
                    Text("settings.website_args.arguments.help")
                }

                Section {
                    Toggle("settings.website_args.enabled", isOn: $rule.isEnabled)
                }
            }
            .navigationTitle(
                isNew ? Text("settings.website_args.new.title") : Text("settings.website_args.edit.title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var patternPlaceholder: LocalizedStringKey {
        switch rule.matchType {
        case .website: return "settings.website_args.pattern.website.placeholder"
        case .regex: return "settings.website_args.pattern.regex.placeholder"
        }
    }

    private var patternHelp: LocalizedStringKey {
        switch rule.matchType {
        case .website: return "settings.website_args.pattern.website.help"
        case .regex: return "settings.website_args.pattern.regex.help"
        }
    }

    private var patternError: LocalizedStringKey {
        switch rule.matchType {
        case .website: return "settings.website_args.pattern.website.invalid"
        case .regex: return "settings.website_args.pattern.regex.invalid"
        }
    }

    private func save() {
        var savedRule = rule
        switch savedRule.matchType {
        case .website:
            savedRule.pattern = WebsiteArgumentRules.normalizedWebsite(savedRule.pattern) ?? savedRule.pattern
        case .regex:
            savedRule.pattern = savedRule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        savedRule.arguments = savedRule.trimmedArguments
        onSave(savedRule)
        dismiss()
    }
}
