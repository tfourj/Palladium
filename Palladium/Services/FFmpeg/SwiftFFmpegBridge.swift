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
    let error: String?
}

@_cdecl("palladium_ffmpeg_bridge_run")
public func palladium_ffmpeg_bridge_run(_ jsonPtr: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let response: FFmpegBridgeResponse

    do {
        guard let jsonPtr else {
            response = FFmpegBridgeResponse(ok: false, exit_code: 1, output: "", error: "missing request payload")
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
            response = FFmpegBridgeResponse(ok: false, exit_code: 1, output: "", error: "unsupported tool: \(request.tool)")
            return makeCString(response)
        }

        do {
            let (exitCode, output) = try SwiftFFmpeg.execute(request.args, tool: tool)
            response = FFmpegBridgeResponse(ok: true, exit_code: Int(exitCode), output: output, error: nil)
        } catch {
            var code = 1
            if let swiftError = error as? SwiftFFmpegError,
               case let .executionFailed(exitCode) = swiftError {
                code = Int(exitCode)
            }
            response = FFmpegBridgeResponse(
                ok: false,
                exit_code: code,
                output: "",
                error: String(describing: error)
            )
        }
    } catch {
        response = FFmpegBridgeResponse(ok: false, exit_code: 1, output: "", error: "invalid request: \(error)")
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
        return strdup("{\"ok\":false,\"exit_code\":1,\"output\":\"\",\"error\":\"encoding failed\"}")
    }
    return strdup(string)
}
