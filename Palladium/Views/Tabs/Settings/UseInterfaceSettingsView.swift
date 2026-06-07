import SwiftUI

struct UseInterfaceSettingsView: View {
    @Binding var checkPackageUpdatesOnLaunch: Bool
    @Binding var selectedPreset: DownloadPreset
    @Binding var afterDownloadBehavior: AfterDownloadBehavior
    @Binding var notificationsEnabled: Bool
    @Binding var rememberSelectedPreset: Bool
    @Binding var autoDownloadOnPaste: Bool
    @Binding var autoRetryFailedDownloads: Bool
    @Binding var detailedProgressEnabled: Bool
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode
    @Binding var linkHistoryEnabled: Bool
    @Binding var linkHistoryLimit: Int
    @Binding var appAppearanceMode: AppAppearanceMode
    @Binding var showTemporaryDownloads: Bool

    @State private var linkHistoryLimitText: String
    @FocusState private var isHistoryLimitFieldFocused: Bool

    let isRunning: Bool

    init(
        checkPackageUpdatesOnLaunch: Binding<Bool>,
        selectedPreset: Binding<DownloadPreset>,
        afterDownloadBehavior: Binding<AfterDownloadBehavior>,
        notificationsEnabled: Binding<Bool>,
        rememberSelectedPreset: Binding<Bool>,
        autoDownloadOnPaste: Binding<Bool>,
        autoRetryFailedDownloads: Binding<Bool>,
        detailedProgressEnabled: Binding<Bool>,
        shareSheetDownloadMode: Binding<ShareSheetDownloadMode>,
        linkHistoryEnabled: Binding<Bool>,
        linkHistoryLimit: Binding<Int>,
        appAppearanceMode: Binding<AppAppearanceMode>,
        showTemporaryDownloads: Binding<Bool>,
        isRunning: Bool
    ) {
        _checkPackageUpdatesOnLaunch = checkPackageUpdatesOnLaunch
        _selectedPreset = selectedPreset
        _afterDownloadBehavior = afterDownloadBehavior
        _notificationsEnabled = notificationsEnabled
        _rememberSelectedPreset = rememberSelectedPreset
        _autoDownloadOnPaste = autoDownloadOnPaste
        _autoRetryFailedDownloads = autoRetryFailedDownloads
        _detailedProgressEnabled = detailedProgressEnabled
        _shareSheetDownloadMode = shareSheetDownloadMode
        _linkHistoryEnabled = linkHistoryEnabled
        _linkHistoryLimit = linkHistoryLimit
        _appAppearanceMode = appAppearanceMode
        _showTemporaryDownloads = showTemporaryDownloads
        _linkHistoryLimitText = State(initialValue: String(linkHistoryLimit.wrappedValue))
        self.isRunning = isRunning
    }

    var body: some View {
        Form {
            Section {
                Picker("settings.ui.modes.normal", selection: $selectedPreset) {
                    ForEach(DownloadPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)

                Picker("settings.ui.modes.share_sheet", selection: $shareSheetDownloadMode) {
                    ForEach(ShareSheetDownloadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)

                Toggle("settings.ui.modes.remember", isOn: $rememberSelectedPreset)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.modes.section")
            } footer: {
                Text("settings.ui.modes.help")
            }

            Section {
                Picker("settings.ui.after_download.picker", selection: $afterDownloadBehavior) {
                    ForEach(AfterDownloadBehavior.allCases) { behavior in
                        Label(behavior.title, systemImage: behavior.icon).tag(behavior)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
            } header: {
                Text("settings.ui.after_download.title")
            } footer: {
                Text("settings.ui.after_download.help")
            }

            Section {
                Picker("settings.ui.appearance.picker", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
            } header: {
                Text("settings.ui.appearance.section")
            } footer: {
                Text("settings.ui.appearance.help")
            }

            Section {
                Toggle("settings.ui.paste.auto_download", isOn: $autoDownloadOnPaste)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.paste.section")
            } footer: {
                Text("settings.ui.paste.help")
            }

            Section {
                Toggle("settings.ui.retry_failed.toggle", isOn: $autoRetryFailedDownloads)
                    .disabled(isRunning)

                Toggle("settings.ui.progress.verbose", isOn: $detailedProgressEnabled)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.progress.section")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings.ui.retry_failed.help")
                    Text("settings.ui.progress.help")
                }
            }

            Section {
                Toggle("settings.ui.downloads.show_temp", isOn: $showTemporaryDownloads)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.downloads.section")
            } footer: {
                Text("settings.ui.downloads.help")
            }

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
            } header: {
                Text("settings.ui.history.section")
            } footer: {
                Text("settings.ui.history.help")
            }

            Section("settings.notifications.title") {
                Toggle("settings.notifications.toggle", isOn: $notificationsEnabled)
                    .disabled(isRunning)
            }

            Section {
                Toggle("settings.ui.packages.auto_check", isOn: $checkPackageUpdatesOnLaunch)
                    .disabled(isRunning)
            } header: {
                Text("settings.maintenance.section")
            } footer: {
                Text("settings.ui.packages.auto_check.help")
            }
        }
        .navigationTitle("settings.ui.title")
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
