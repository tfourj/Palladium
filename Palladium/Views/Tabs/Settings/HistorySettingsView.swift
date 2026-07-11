import SwiftUI

struct HistorySettingsView: View {
    @Binding var linkHistoryEnabled: Bool
    @Binding var linkHistoryLimit: Int
    @Binding var hideHistoryCount: Bool

    @State private var linkHistoryLimitText: String
    @FocusState private var isHistoryLimitFieldFocused: Bool

    let isRunning: Bool

    init(
        linkHistoryEnabled: Binding<Bool>,
        linkHistoryLimit: Binding<Int>,
        hideHistoryCount: Binding<Bool>,
        isRunning: Bool
    ) {
        _linkHistoryEnabled = linkHistoryEnabled
        _linkHistoryLimit = linkHistoryLimit
        _hideHistoryCount = hideHistoryCount
        _linkHistoryLimitText = State(initialValue: String(linkHistoryLimit.wrappedValue))
        self.isRunning = isRunning
    }

    var body: some View {
        Form {
            Section {
                Toggle("settings.ui.history.enable", isOn: $linkHistoryEnabled)
                    .disabled(isRunning)

                HStack {
                    Text("settings.ui.history.limit")
                    Spacer()
                    TextField("0", text: $linkHistoryLimitText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.blue)
                        .frame(width: 64)
                        .focused($isHistoryLimitFieldFocused)
                        .onChange(of: linkHistoryLimitText) { _, newValue in
                            let filteredValue = newValue.filter(\.isNumber)
                            if filteredValue != newValue {
                                linkHistoryLimitText = filteredValue
                            }
                        }
                        .onSubmit(commitLinkHistoryLimit)
                }
                .disabled(isRunning || !linkHistoryEnabled)

                Toggle("settings.ui.history.hide_count", isOn: $hideHistoryCount)
                    .disabled(isRunning || !linkHistoryEnabled)
            } header: {
                Text("settings.ui.history.section")
            } footer: {
                Text("settings.ui.history.help")
            }
        }
        .navigationTitle("settings.ui.history.section")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncLinkHistoryLimitText()
        }
        .onChange(of: linkHistoryLimit) { _, _ in
            guard !isHistoryLimitFieldFocused else { return }
            syncLinkHistoryLimitText()
        }
        .onChange(of: isHistoryLimitFieldFocused) { _, isFocused in
            guard !isFocused else { return }
            commitLinkHistoryLimit()
        }
    }

    private func syncLinkHistoryLimitText() {
        linkHistoryLimitText = String(linkHistoryLimit)
    }

    private func commitLinkHistoryLimit() {
        let trimmedValue = linkHistoryLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedValue = Int(trimmedValue) ?? 0
        let clampedValue = min(max(parsedValue, 0), ContentView.maxLinkHistoryLimit)

        if linkHistoryLimit != clampedValue {
            linkHistoryLimit = clampedValue
        }

        let normalizedText = String(clampedValue)
        if linkHistoryLimitText != normalizedText {
            linkHistoryLimitText = normalizedText
        }
    }
}
