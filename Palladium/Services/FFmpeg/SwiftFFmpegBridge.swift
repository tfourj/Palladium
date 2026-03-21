import Foundation
import SwiftFFmpeg
import Darwin

private struct FFmpegBridgeRequest: Decodable {
    let tool: String
    let args: [String]
}

private struct FFmpegBridgeResponse: Encodable {
    let ok: Bool
    let exit_code: Int
    let output: String
    let stderr: String
    let error: String?
}

enum FFmpegBridgeControl {
    static func requestCancellation() {
        SwiftFFmpeg.requestCancel()
    }
}

private final class FFmpegLiveLogForwarder {
    private let liveLogFD: Int32?
    private let lock = NSLock()
    private var pendingMessage = ""

    init() {
        if let rawValue = ProcessInfo.processInfo.environment["PALLADIUM_LOG_FD"],
           let fdValue = Int32(rawValue) {
            liveLogFD = fdValue
        } else {
            liveLogFD = nil
        }
    }

    func ingest(_ message: String) {
        guard liveLogFD != nil else { return }
        var linesToEmit: [String] = []
        lock.lock()
        pendingMessage.append(message)

        while let newlineIndex = pendingMessage.firstIndex(where: \.isNewline) {
            let line = String(pendingMessage[..<newlineIndex])
            let nextIndex = pendingMessage.index(after: newlineIndex)
            pendingMessage.removeSubrange(pendingMessage.startIndex..<nextIndex)
            linesToEmit.append(line)
        }
        lock.unlock()

        for line in linesToEmit {
            emitIfRelevant(line)
        }
    }

    func finish() {
        let trailingLine: String?
        lock.lock()
        trailingLine = pendingMessage.isEmpty ? nil : pendingMessage
        pendingMessage.removeAll(keepingCapacity: false)
        lock.unlock()

        if let trailingLine {
            emitIfRelevant(trailingLine)
        }
    }

    private func emitIfRelevant(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let duration = extractMatch(#"Duration:\s*([0-9:.]+)"#, from: trimmed) {
            writeLine("[palladium][ffmpeg-progress] duration=\(duration)")
            return
        }

        if let currentTime = extractMatch(#"time=([0-9:.]+)"#, from: trimmed) {
            let speed = extractMatch(#"speed=\s*([0-9.]+x)"#, from: trimmed) ?? ""
            let suffix = speed.isEmpty ? "" : " speed=\(speed)"
            writeLine("[palladium][ffmpeg-progress] time=\(currentTime)\(suffix)")
        }
    }

    private func extractMatch(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }

    private func writeLine(_ line: String) {
        guard let liveLogFD,
              let data = "\(line)\n".data(using: .utf8) else {
            return
        }
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = Darwin.write(liveLogFD, baseAddress, buffer.count)
        }
    }
}

@_cdecl("palladium_ffmpeg_bridge_run")
public func palladium_ffmpeg_bridge_run(_ jsonPtr: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let response: FFmpegBridgeResponse

    do {
        guard let jsonPtr else {
            response = FFmpegBridgeResponse(ok: false, exit_code: 1, output: "", stderr: "", error: "missing request payload")
            return makeCString(response)
        }

        let inputData = Data(bytes: jsonPtr, count: strlen(jsonPtr))
        let request = try JSONDecoder().decode(FFmpegBridgeRequest.self, from: inputData)

        let tool: FFmpegTool
        switch request.tool {
        case "ffmpeg":
            tool = .ffmpeg
        case "ffprobe":
            tool = .ffprobe
        default:
            response = FFmpegBridgeResponse(ok: false, exit_code: 1, output: "", stderr: "", error: "unsupported tool: \(request.tool)")
            return makeCString(response)
        }

        let liveLogForwarder = tool == .ffmpeg ? FFmpegLiveLogForwarder() : nil
        do {
            SwiftFFmpeg.setLogHandler { _, message in
                liveLogForwarder?.ingest(message)
            }
            let result = try SwiftFFmpeg.executeDetailed(request.args, tool: tool)
            liveLogForwarder?.finish()
            SwiftFFmpeg.setLogHandler(nil)
            response = FFmpegBridgeResponse(
                ok: true,
                exit_code: Int(result.exitCode),
                output: result.stdout,
                stderr: result.stderr,
                error: nil
            )
        } catch {
            liveLogForwarder?.finish()
            SwiftFFmpeg.setLogHandler(nil)
            var code = 1
            var output = ""
            var stderr = ""
            if let swiftError = error as? SwiftFFmpegError,
               case let .executionFailed(exitCode, capturedStdout, capturedStderr) = swiftError {
                code = Int(exitCode)
                output = capturedStdout
                stderr = capturedStderr
            }
            response = FFmpegBridgeResponse(
                ok: false,
                exit_code: code,
                output: output,
                stderr: stderr,
                error: String(describing: error)
            )
        }
    } catch {
        response = FFmpegBridgeResponse(ok: false, exit_code: 1, output: "", stderr: "", error: "invalid request: \(error)")
    }

    return makeCString(response)
}

@_cdecl("palladium_ffmpeg_bridge_free")
public func palladium_ffmpeg_bridge_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    guard let ptr else { return }
    free(ptr)
}

private var ffmpegBridgeRunAnchor: ((UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?)?
private var ffmpegBridgeFreeAnchor: ((UnsafeMutablePointer<CChar>?) -> Void)?

@inline(never)
func retainFFmpegBridgeExports() {
    // Keep explicit references so release builds preserve exported C bridge symbols.
    ffmpegBridgeRunAnchor = palladium_ffmpeg_bridge_run
    ffmpegBridgeFreeAnchor = palladium_ffmpeg_bridge_free
}

private func makeCString(_ response: FFmpegBridgeResponse) -> UnsafeMutablePointer<CChar>? {
    guard let data = try? JSONEncoder().encode(response),
          let string = String(data: data, encoding: .utf8) else {
        return strdup("{\"ok\":false,\"exit_code\":1,\"output\":\"\",\"stderr\":\"\",\"error\":\"encoding failed\"}")
    }
    return strdup(string)
}
