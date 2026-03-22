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
            Text("post_download.title")
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
                    title: completedResultIsCollection ? String(localized: "post_download.action.share_all.title") : String(localized: "post_download.action.share.title"),
                    subtitle: completedResultIsCollection ? String(localized: "post_download.action.share_all.help") : String(localized: "post_download.action.share.help"),
                    icon: "square.and.arrow.up",
                    color: .blue
                ) {
                    performPromptedPostDownloadAction(.openShareSheet)
                }

                if shouldOfferPhotosAction {
                    downloadCompleteActionButton(
                        title: String(localized: "photos.action.save"),
                        subtitle: saveToPhotosButtonSubtitle,
                        icon: "photo.on.rectangle",
                        color: .green,
                        isEnabled: completedPhotosCompatibility.isCompatible
                    ) {
                        performPromptedPostDownloadAction(.saveToPhotos)
                    }
                }

                downloadCompleteActionButton(
                    title: String(localized: "post_download.action.save_folder.title"),
                    subtitle: completedResultIsCollection
                        ? String(localized: "post_download.action.save_folder.collection_help")
                        : String(localized: "post_download.action.save_folder.help"),
                    icon: "folder.badge.plus",
                    color: .orange
                ) {
                    performPromptedPostDownloadAction(.saveToApplicationFolder)
                }
            }
            .padding(.horizontal)

            Button(action: dismissDownloadActionSheet) {
                Text("common.cancel")
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
            return String(localized: "post_download.summary.collection")
        }
        if result.isCollection {
            return String(format: String(localized: "post_download.summary.collection_count"), result.items.count)
        }
        return String(localized: "post_download.summary.single")
    }

    var saveToPhotosButtonSubtitle: String {
        switch completedPhotosCompatibility {
        case .checking:
            return String(localized: "photos.compatibility.checking")
        case .compatible(let mediaType):
            switch mediaType {
            case .video:
                return String(localized: "photos.action.import_video")
            case .image:
                return String(localized: "photos.action.import_image")
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
                    reason = String(localized: "photos.compatibility.unknown")
                }
                await MainActor.run {
                    reopenDownloadActionAfterAlert = true
                    alertMessage = String(format: String(localized: "photos.error.import_reason"), reason)
                    showAlert = true
                }
                return
            }

            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                await MainActor.run {
                    reopenDownloadActionAfterAlert = true
                    alertMessage = String(localized: "photos.error.permission")
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
                    showTemporaryToast(String(localized: "photos.toast.saved"))
                }
            } catch {
                await MainActor.run {
                    reopenDownloadActionAfterAlert = true
                    alertMessage = String(format: String(localized: "photos.error.save"), error.localizedDescription)
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
            return isImageIOSCompatible(fileURL)
                ? .compatible(.image)
                : .incompatible(String(format: String(localized: "photos.error.unsupported_image_format"), ext))
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

        return .incompatible(
            String(format: String(localized: "photos.error.unsupported_format"), ext.isEmpty ? "unknown" : ext)
        )
    }

    func videoCompatibilityState(for fileURL: URL) async -> PhotosCompatibilityState {
        let ext = fileURL.pathExtension.lowercased()
        let compatibleExtensions: Set<String> = ["mp4", "mov", "m4v"]
        guard compatibleExtensions.contains(ext) else {
            return .incompatible(String(localized: "photos.error.video_format"))
        }

        if UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(fileURL.path) {
            return .compatible(.video)
        }

        do {
            let asset = AVAsset(url: fileURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else {
                return .incompatible(String(localized: "photos.error.no_video_track"))
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

            return .incompatible(String(localized: "photos.error.codec"))
        } catch {
            return .incompatible(String(localized: "photos.error.inspect_codec"))
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
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "post_download.error.no_files")]
                )
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            alertMessage = nil
            showAlert = false
            if result.isCollection {
                showTemporaryToast(
                    String(format: String(localized: "post_download.toast.saved_folder_name"), destination.lastPathComponent)
                )
            } else {
                showTemporaryToast(
                    String(format: String(localized: "post_download.toast.saved_folder"), destination.lastPathComponent)
                )
            }
        } catch {
            alertMessage = String(format: String(localized: "post_download.error.save_folder"), error.localizedDescription)
            showAlert = true
        }
    }

    func handlePostDownloadAction(_ action: PostDownloadAction, for result: CompletedDownloadResult) {
        switch action {
        case .saveToPhotos:
            guard let fileURL = result.photosCandidateURL else {
                reopenDownloadActionAfterAlert = true
                alertMessage = String(localized: "photos.error.single_only")
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
        return String(localized: "download.fallback_title")
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
