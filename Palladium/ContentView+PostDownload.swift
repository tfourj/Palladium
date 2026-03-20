//
//  ContentView+PostDownload.swift
//  Palladium
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

extension ContentView {
    var downloadCompleteActionSheet: some View {
        VStack(spacing: 20) {
            Text("Download Complete")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)

            if let summaryTitle = completedResultDisplayTitle {
                Text(summaryTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal)
            }

            Text(downloadCompleteSummaryText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 14) {
                downloadCompleteActionButton(
                    title: completedResultIsCollection ? "Share All" : "Open Share Sheet",
                    subtitle: completedResultIsCollection ? "Share every downloaded file" : "Share or save with other apps",
                    icon: "square.and.arrow.up",
                    color: .blue
                ) {
                    performPromptedPostDownloadAction(.openShareSheet)
                }

                if shouldOfferPhotosAction {
                    downloadCompleteActionButton(
                        title: "Save to Photos",
                        subtitle: saveToPhotosButtonSubtitle,
                        icon: "photo.on.rectangle",
                        color: .green,
                        isEnabled: completedPhotosCompatibility.isCompatible
                    ) {
                        performPromptedPostDownloadAction(.saveToPhotos)
                    }
                }

                downloadCompleteActionButton(
                    title: "Save to App Folder",
                    subtitle: completedResultIsCollection
                        ? "Keep the whole download folder in Palladium/Saved"
                        : "Keep a copy in Palladium/Saved",
                    icon: "folder.badge.plus",
                    color: .orange
                ) {
                    performPromptedPostDownloadAction(.saveToApplicationFolder)
                }
            }
            .padding(.horizontal)

            Button(action: dismissDownloadActionSheet) {
                Text("Cancel")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
        .presentationDetents([.fraction(0.58), .large])
        .presentationDragIndicator(.hidden)
    }

    func downloadCompleteActionButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.45)
    }

    func performPromptedPostDownloadAction(_ action: PostDownloadAction) {
        guard let result = completedDownloadResult else {
            showDownloadActionSheet = false
            return
        }
        showDownloadActionSheet = false
        handlePostDownloadAction(action, for: result)
    }

    var completedResultDisplayTitle: String? {
        guard let result = completedDownloadResult else { return nil }
        if let titleHint = result.titleHint, !titleHint.isEmpty {
            return titleHint
        }
        if !result.isCollection {
            return result.primaryMediaURL?.lastPathComponent ?? result.items.first?.lastPathComponent
        }
        if let primaryMediaURL = result.primaryMediaURL {
            return primaryMediaURL.deletingPathExtension().lastPathComponent
        }
        return result.folderURL?.lastPathComponent
    }

    var completedResultIsCollection: Bool {
        completedDownloadResult?.isCollection ?? false
    }

    var shouldOfferPhotosAction: Bool {
        guard let result = completedDownloadResult else { return false }
        return !result.isCollection
    }

    var downloadCompleteSummaryText: String {
        guard let result = completedDownloadResult else {
            return "Choose what to do with the downloaded files."
        }
        if result.isCollection {
            return "This download produced \(result.items.count) files. Photos import is disabled for collections and subtitle sidecars."
        }
        return "Choose what to do with the downloaded file."
    }

    var saveToPhotosButtonSubtitle: String {
        switch completedPhotosCompatibility {
        case .checking:
            return "Checking compatibility..."
        case .compatible(let mediaType):
            switch mediaType {
            case .video:
                return "Import video into Photos library"
            case .image:
                return "Import image into Photos library"
            }
        case .incompatible(let reason):
            return reason
        }
    }

    func dismissDownloadActionSheet() {
        showDownloadActionSheet = false
        completedDownloadResult = nil
        completedPhotosCompatibility = .checking
    }

    func saveDownloadedFileToPhotos(_ url: URL) {
        Task {
            let compatibility = await evaluatePhotosCompatibility(for: url)
            guard case .compatible(let mediaType) = compatibility else {
                let reason: String
                if case .incompatible(let details) = compatibility {
                    reason = details
                } else {
                    reason = "Could not verify media compatibility."
                }
                await MainActor.run {
                    reopenDownloadActionAfterAlert = true
                    alertMessage = "iOS Photos cannot import this file: \(reason)"
                    showAlert = true
                }
                return
            }

            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                await MainActor.run {
                    reopenDownloadActionAfterAlert = true
                    alertMessage = "Photo library permission was denied."
                    showAlert = true
                }
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    switch mediaType {
                    case .video:
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    case .image:
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                    }
                }
                await MainActor.run {
                    reopenDownloadActionAfterAlert = false
                    alertMessage = nil
                    showAlert = false
                    showTemporaryToast("Saved to Photos")
                }
            } catch {
                await MainActor.run {
                    reopenDownloadActionAfterAlert = true
                    alertMessage = "Failed to save to Photos: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func evaluatePhotosCompatibility(for fileURL: URL) async -> PhotosCompatibilityState {
        let ext = fileURL.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heif", "heic"]
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "flv", "ts", "mpeg", "mpg"]

        if imageExtensions.contains(ext) {
            return isImageIOSCompatible(fileURL) ? .compatible(.image) : .incompatible("Unsupported image format (\(ext)).")
        }

        if videoExtensions.contains(ext) {
            return await videoCompatibilityState(for: fileURL)
        }

        if isImageIOSCompatible(fileURL) {
            return .compatible(.image)
        }

        let fallbackVideo = await videoCompatibilityState(for: fileURL)
        if fallbackVideo.isCompatible {
            return fallbackVideo
        }

        return .incompatible("Unsupported format (\(ext.isEmpty ? "unknown" : ext)).")
    }

    func videoCompatibilityState(for fileURL: URL) async -> PhotosCompatibilityState {
        let ext = fileURL.pathExtension.lowercased()
        let compatibleExtensions: Set<String> = ["mp4", "mov", "m4v"]
        guard compatibleExtensions.contains(ext) else {
            return .incompatible("Only MP4, MOV, or M4V can be saved.")
        }

        if UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(fileURL.path) {
            return .compatible(.video)
        }

        do {
            let asset = AVAsset(url: fileURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else {
                return .incompatible("No video track found.")
            }

            for track in tracks {
                let formatDescriptions = try await track.load(.formatDescriptions)
                for formatDescription in formatDescriptions {
                    let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
                    let codecString = fourCC(codecType)
                    if codecString == "avc1" || codecString == "avc3" ||
                        codecString == "hvc1" || codecString == "hev1" {
                        return .compatible(.video)
                    }
                }
            }

            return .incompatible("Video codec must be H.264 or H.265.")
        } catch {
            return .incompatible("Failed to inspect media codec.")
        }
    }

    func isImageIOSCompatible(_ fileURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        let compatibleExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heif", "heic"]
        if compatibleExtensions.contains(ext) {
            return true
        }
        return UIImage(contentsOfFile: fileURL.path) != nil
    }

    func saveDownloadedFileToApplicationFolder(_ result: CompletedDownloadResult) {
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appFolder = documents.appendingPathComponent("Saved", isDirectory: true)
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

            let sourceURL: URL
            let destination: URL
            if result.isCollection, let folderURL = result.folderURL {
                sourceURL = folderURL
                destination = appFolder.appendingPathComponent(result.savedFolderName, isDirectory: true)
            } else if let itemURL = result.primaryMediaURL ?? result.items.first {
                sourceURL = itemURL
                destination = appFolder.appendingPathComponent(itemURL.lastPathComponent)
            } else {
                throw NSError(
                    domain: "Palladium",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No downloaded files were available."]
                )
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            alertMessage = nil
            showAlert = false
            if result.isCollection {
                showTemporaryToast("Saved folder: \(destination.lastPathComponent)")
            } else {
                showTemporaryToast("Saved to app folder: \(destination.lastPathComponent)")
            }
        } catch {
            alertMessage = "Failed to save to app folder: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func handlePostDownloadAction(_ action: PostDownloadAction, for result: CompletedDownloadResult) {
        switch action {
        case .saveToPhotos:
            guard let fileURL = result.photosCandidateURL else {
                reopenDownloadActionAfterAlert = true
                alertMessage = "Photos is only available for a single media file."
                showAlert = true
                return
            }
            saveDownloadedFileToPhotos(fileURL)
        case .openShareSheet:
            sharePayload = SharePayload(activityItems: result.shareActivityItems)
        case .saveToApplicationFolder:
            saveDownloadedFileToApplicationFolder(result)
        }
    }
}

struct CompletedDownloadResult {
    let items: [URL]
    let primaryMediaURL: URL?
    let folderURL: URL?
    let titleHint: String?

    var isCollection: Bool {
        items.count > 1
    }

    var photosCandidateURL: URL? {
        guard !isCollection else { return nil }
        return primaryMediaURL ?? items.first
    }

    var notificationTargetURL: URL? {
        primaryMediaURL ?? items.first
    }

    var shareActivityItems: [Any] {
        items.map { $0 as Any }
    }

    var savedFolderName: String {
        if let titleHint = sanitizedFolderName(titleHint) {
            return titleHint
        }
        if let primaryMediaURL {
            let baseName = primaryMediaURL.deletingPathExtension().lastPathComponent
            if let sanitized = sanitizedFolderName(baseName) {
                return sanitized
            }
        }
        if let folderURL,
           let sanitized = sanitizedFolderName(folderURL.lastPathComponent) {
            return sanitized
        }
        return "download"
    }

    private func sanitizedFolderName(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = trimmed.components(separatedBy: invalidCharacters)
        let joined = components.joined(separator: " ")
        let collapsed = joined.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ".")))

        return collapsed.isEmpty ? nil : collapsed
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
