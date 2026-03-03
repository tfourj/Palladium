import SwiftUI

struct ConsoleTabView: View {
    @Binding var consoleLogText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("console")
                    .font(.title2.bold())
                Spacer()
                Button("Clear") {
                    consoleLogText = ""
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                Text(consoleLogText.isEmpty ? "No logs yet." : consoleLogText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }
}
