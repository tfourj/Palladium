#if DEBUG
import SwiftFFmpeg
import SwiftUI

struct DeveloperFrameworkDebugView: View {
    let framework: DeveloperFramework
    let store: DeveloperDiagnosticsStore

    private var checks: [DeveloperDiagnosticCheck] {
        DeveloperDiagnostics.checks(for: framework)
    }

    var body: some View {
        List {
            if framework == .app {
                Section {
                    ForEach(DeveloperDiagnostics.appDetails()) { detail in
                        DeveloperDetailRow(detail: detail)
                    }
                } header: {
                    Text(verbatim: "Build")
                }
            } else {
                Section {
                    ForEach(checks) { check in
                        DeveloperCheckLink(check: check, store: store)
                    }
                } header: {
                    Text(verbatim: "Checks")
                }

                if let infoCheck = checks.first, let result = store.results[infoCheck.id], !result.details.isEmpty {
                    Section {
                        ForEach(result.details) { detail in
                            DeveloperDetailRow(detail: detail)
                        }
                    } header: {
                        Text(verbatim: "Info")
                    }
                }

                DeveloperPlaygroundSection(framework: framework)
            }
        }
        .navigationTitle(Text(verbatim: framework.title))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let infoCheck = checks.first, store.results[infoCheck.id] == nil else { return }
            await store.run(infoCheck)
        }
    }
}

private enum DeveloperFFmpegTool: String, CaseIterable, Identifiable {
    case ffmpeg
    case ffprobe

    var id: String { rawValue }

    var tool: FFmpegTool {
        self == .ffmpeg ? .ffmpeg : .ffprobe
    }
}

private struct DeveloperPlaygroundSection: View {
    let framework: DeveloperFramework

    @State private var pythonSource = DeveloperDiagnostics.defaultPythonSource
    @State private var javaScriptSource = DeveloperDiagnostics.defaultJavaScriptSource
    @State private var ffmpegTool = DeveloperFFmpegTool.ffmpeg
    @State private var ffmpegArguments = "-hide_banner -encoders"
    @State private var curlURL = DeveloperDiagnostics.defaultCurlURL
    @State private var impersonateTarget = DeveloperDiagnostics.defaultImpersonateTarget
    @State private var isRunning = false
    @State private var result: DeveloperDiagnosticResult?

    var body: some View {
        Section {
            inputs
            if isRunning {
                HStack {
                    ProgressView()
                    Text(verbatim: "Running")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(verbatim: "Playground")
        }

        if let result, !isRunning {
            DeveloperResultSections(result: result)
        }
    }

    @ViewBuilder
    private var inputs: some View {
        switch framework {
        case .python:
            codeEditor($pythonSource)
            runButton("Run Python") {
                await DeveloperDiagnostics.python("python_eval", argument: ["source": pythonSource])
            }
        case .quickJS:
            codeEditor($javaScriptSource)
            runButton("Run natively") {
                await DeveloperDiagnostics.quickJS(["operation": "evaluate", "source": javaScriptSource])
            }
            runButton("Run through Python bridge") {
                await DeveloperDiagnostics.python("quickjs_bridge", argument: ["source": javaScriptSource])
            }
        case .ffmpeg:
            Picker(selection: $ffmpegTool) {
                ForEach(DeveloperFFmpegTool.allCases) { tool in
                    Text(verbatim: tool.rawValue).tag(tool)
                }
            } label: {
                Text(verbatim: "Tool")
            }
            .pickerStyle(.segmented)
            plainTextField("Arguments", text: $ffmpegArguments)
            runButton("Run \(ffmpegTool.rawValue)") {
                let arguments = ffmpegArguments.split(whereSeparator: \.isWhitespace).map(String.init)
                return await DeveloperDiagnostics.ffmpeg(tool: ffmpegTool.tool, arguments: arguments)
            }
        case .curlCffi:
            plainTextField("URL", text: $curlURL)
                .keyboardType(.URL)
            plainTextField("Impersonate target (empty for none)", text: $impersonateTarget)
            runButton("Send request") {
                await DeveloperDiagnostics.curlRequest(url: curlURL, impersonate: impersonateTarget)
            }
        case .app:
            EmptyView()
        }
    }

    private func codeEditor(_ text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.system(.footnote, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: 140)
    }

    private func plainTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(text: text) {
            Text(verbatim: placeholder)
        }
        .font(.system(.footnote, design: .monospaced))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func runButton(
        _ title: String,
        action: @escaping () async -> DeveloperDiagnosticResult
    ) -> some View {
        Button {
            Task {
                isRunning = true
                result = await action()
                isRunning = false
            }
        } label: {
            Text(verbatim: title)
        }
        .disabled(isRunning)
    }
}
#endif
