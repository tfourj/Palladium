#if DEBUG
import SwiftUI
import UIKit

@Observable
final class DeveloperDiagnosticsStore {
    private(set) var results: [String: DeveloperDiagnosticResult] = [:]
    private(set) var runningIDs: Set<String> = []
    private(set) var isRunningAll = false

    func isRunning(_ check: DeveloperDiagnosticCheck) -> Bool {
        runningIDs.contains(check.id)
    }

    func run(_ check: DeveloperDiagnosticCheck) async {
        guard !runningIDs.contains(check.id) else { return }
        runningIDs.insert(check.id)
        let result = await check.run()
        results[check.id] = result
        runningIDs.remove(check.id)
    }

    func runAll() async {
        guard !isRunningAll else { return }
        isRunningAll = true
        for check in DeveloperDiagnostics.standardChecks {
            await run(check)
        }
        isRunningAll = false
    }

    var summary: String {
        let finished = DeveloperDiagnostics.standardChecks.compactMap { results[$0.id] }
        let passed = finished.filter(\.ok).count
        return "\(passed) of \(finished.count) passed"
    }

    func report() -> String {
        var sections = ["# App"] + DeveloperDiagnostics.appDetails().map { "\($0.key): \($0.value)" }
        for check in DeveloperDiagnostics.standardChecks {
            sections.append("\n# \(check.framework.title): \(check.title)")
            sections.append(results[check.id]?.report ?? "not run")
        }
        return sections.joined(separator: "\n")
    }
}

struct DeveloperDebugMenuView: View {
    let store: DeveloperDiagnosticsStore
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await store.runAll() }
                    } label: {
                        HStack {
                            Label {
                                Text(verbatim: "Run all checks")
                            } icon: {
                                Image(systemName: "play.circle")
                            }
                            Spacer()
                            if store.isRunningAll {
                                ProgressView()
                            } else if !store.results.isEmpty {
                                Text(verbatim: store.summary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(store.isRunningAll)

                    ForEach(DeveloperDiagnostics.standardChecks) { check in
                        DeveloperCheckLink(check: check, store: store, showsFramework: true)
                    }
                } header: {
                    Text(verbatim: "Checks")
                } footer: {
                    Text(verbatim: "Avoid running checks during a download. Native FFmpeg runs share global state.")
                }

                Section {
                    ForEach(DeveloperFramework.allCases) { framework in
                        NavigationLink {
                            DeveloperFrameworkDebugView(framework: framework, store: store)
                        } label: {
                            Label {
                                Text(verbatim: framework.title)
                            } icon: {
                                Image(systemName: framework.systemImage)
                            }
                        }
                    }
                } header: {
                    Text(verbatim: "Frameworks")
                }
            }
            .navigationTitle(Text(verbatim: "Developer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Text(verbatim: "Done")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = store.report()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel(Text(verbatim: "Copy report"))
                }
            }
        }
    }
}

struct DeveloperCheckLink: View {
    let check: DeveloperDiagnosticCheck
    let store: DeveloperDiagnosticsStore
    var showsFramework = false

    var body: some View {
        if let result = store.results[check.id], !store.isRunning(check) {
            NavigationLink {
                DeveloperDiagnosticResultView(title: check.title, result: result) {
                    Task { await store.run(check) }
                }
            } label: {
                row(result: result)
            }
        } else {
            Button {
                Task { await store.run(check) }
            } label: {
                row(result: nil)
            }
            .tint(.primary)
            .disabled(store.isRunning(check))
        }
    }

    private func row(result: DeveloperDiagnosticResult?) -> some View {
        HStack(spacing: 12) {
            DeveloperStatusIcon(result: result, isRunning: store.isRunning(check))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: check.title)
                    .foregroundStyle(.primary)
                if showsFramework {
                    Text(verbatim: check.framework.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let result {
                Text(verbatim: "\(result.durationMS) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DeveloperStatusIcon: View {
    let result: DeveloperDiagnosticResult?
    let isRunning: Bool

    var body: some View {
        Group {
            if isRunning {
                ProgressView()
            } else if let result {
                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(result.ok ? .green : .red)
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22)
    }
}

struct DeveloperDiagnosticResultView: View {
    let title: String
    let result: DeveloperDiagnosticResult
    var onRerun: (() -> Void)?

    var body: some View {
        List {
            DeveloperResultSections(result: result)
        }
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let onRerun {
                    Button(action: onRerun) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(Text(verbatim: "Run again"))
                }
                Button {
                    UIPasteboard.general.string = result.report
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(Text(verbatim: "Copy result"))
            }
        }
    }
}

struct DeveloperResultSections: View {
    let result: DeveloperDiagnosticResult

    var body: some View {
        Section {
            HStack {
                DeveloperStatusIcon(result: result, isRunning: false)
                Text(verbatim: result.ok ? "Passed" : "Failed")
                Spacer()
                Text(verbatim: "\(result.durationMS) ms")
                    .foregroundStyle(.secondary)
            }
            if let error = result.error {
                DeveloperValueText(value: error)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(verbatim: "Status")
        }

        if !result.details.isEmpty {
            Section {
                ForEach(result.details) { detail in
                    DeveloperDetailRow(detail: detail)
                }
            } header: {
                Text(verbatim: "Details")
            }
        }

        if !result.output.isEmpty {
            Section {
                DeveloperValueText(value: result.output)
            } header: {
                Text(verbatim: "Output")
            }
        }
    }
}

struct DeveloperDetailRow: View {
    let detail: DeveloperDiagnosticDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: detail.key)
                .font(.caption)
                .foregroundStyle(.secondary)
            DeveloperValueText(value: detail.value)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = detail.value
            } label: {
                Label {
                    Text(verbatim: "Copy")
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }
}

struct DeveloperValueText: View {
    let value: String

    var body: some View {
        Text(verbatim: value)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
