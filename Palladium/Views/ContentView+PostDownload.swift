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
            Text(downloadCompleteTitle)
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

                if completedDownloadAllowsSaveToApplicationFolder {
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
            }
            .padding(.horizontal)

            Button(action: dismissDownloadActionSheet) {
                Text(postDownloadDismissButtonTitle)
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
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer()
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
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
        switch action {
        case .saveToPhotos:
            handlePostDownloadAction(action, for: result) {
                advancePostDownloadPromptSequence()
            }
        case .openShareSheet:
            advancePostDownloadAfterSharing = true
            handlePostDownloadAction(action, for: result)
        case .saveToApplicationFolder:
            if saveDownloadedFileToApplicationFolder(result) {
                advancePostDownloadAfterActionSheetDismissal = true
            } else {
                reopenDownloadActionAfterAlert = true
            }
        }
    }

    var downloadCompleteTitle: String {
        completedDownloadResult?.mediaGroup?.completionTitle
            ?? String(localized: "post_download.title")
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
        if let mediaGroup = result.mediaGroup {
            return mediaGroup.supportsPhotos
        }
        return !result.items.isEmpty
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

    var postDownloadDismissButtonTitle: String {
        pendingPostDownloadResults.isEmpty
            ? String(localized: "common.cancel")
            : String(localized: "post_download.action.skip")
    }

    func dismissDownloadActionSheet() {
        advancePostDownloadAfterActionSheetDismissal = !pendingPostDownloadResults.isEmpty
        showDownloadActionSheet = false
        guard pendingPostDownloadResults.isEmpty else { return }
        resetPostDownloadPromptSequence()
    }

    func beginPostDownloadPromptSequence(with results: [CompletedDownloadResult]) {
        guard let firstResult = results.first else {
            resetPostDownloadPromptSequence()
            return
        }
        pendingPostDownloadResults = Array(results.dropFirst())
        presentPostDownloadPrompt(for: firstResult)
    }

    func advancePostDownloadPromptSequence() {
        guard !pendingPostDownloadResults.isEmpty else {
            resetPostDownloadPromptSequence()
            return
        }
        let nextResult = pendingPostDownloadResults.removeFirst()
        presentPostDownloadPrompt(for: nextResult)
    }

    private func presentPostDownloadPrompt(for result: CompletedDownloadResult) {
        completedDownloadResult = result
        completedPhotosCompatibility = .checking
        showDownloadActionSheet = true

        guard result.mediaGroup?.supportsPhotos != false else {
            completedPhotosCompatibility = .incompatible(
                String(localized: "photos.error.unsupported_media_group")
            )
            return
        }

        Task {
            let compatibility = await evaluatePhotosCompatibility(for: result)
            await MainActor.run {
                guard completedDownloadResult?.id == result.id else { return }
                completedPhotosCompatibility = compatibility
            }
        }
    }

    private func resetPostDownloadPromptSequence() {
        pendingPostDownloadResults = []
        completedDownloadResult = nil
        completedDownloadAllowsSaveToApplicationFolder = true
        completedPhotosCompatibility = .checking
        advancePostDownloadAfterActionSheetDismissal = false
        advancePostDownloadAfterSharing = false
    }

    func openSavedDownloadActions(_ item: SavedDownloadItem) {
        pendingPostDownloadResults = []
        completedDownloadAllowsSaveToApplicationFolder = item.location != .saved
        completedDownloadResult = CompletedDownloadResult(
            items: [item.url],
            primaryMediaURL: item.url,
            folderURL: nil,
            titleHint: item.displayName,
            sourceURL: nil
        )
        completedPhotosCompatibility = .checking
        showDownloadActionSheet = true

        Task {
            let compatibility = await evaluatePhotosCompatibility(for: item.url)
            await MainActor.run {
                guard completedDownloadResult?.primaryMediaURL == item.url else { return }
                completedPhotosCompatibility = compatibility
            }
        }
    }

    func saveDownloadedFileToPhotos(
        _ url: URL,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
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
                    onSuccess?()
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

    func saveDownloadedFilesToPhotos(
        _ urls: [URL],
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        Task {
            var compatible: [(URL, PhotosMediaType)] = []
            for url in urls {
                let state = await evaluatePhotosCompatibility(for: url)
                if case .compatible(let mediaType) = state {
                    compatible.append((url, mediaType))
                }
            }
            guard compatible.count == urls.count else {
                await MainActor.run {
                    reopenDownloadActionAfterAlert = true
                    alertMessage = String(localized: "photos.error.mixed_collection")
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
                    for (url, mediaType) in compatible {
                        switch mediaType {
                        case .image:
                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                        case .video:
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                        }
                    }
                }
                await MainActor.run {
                    showTemporaryToast(String(localized: "photos.toast.saved"))
                    onSuccess?()
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

    func evaluatePhotosCompatibility(for result: CompletedDownloadResult) async -> PhotosCompatibilityState {
        guard let firstItem = result.items.first else {
            return .incompatible(String(localized: "post_download.error.no_files"))
        }

        let firstCompatibility = await evaluatePhotosCompatibility(for: firstItem)
        guard case .compatible(let expectedMediaType) = firstCompatibility else {
            return firstCompatibility
        }

        for item in result.items.dropFirst() {
            let compatibility = await evaluatePhotosCompatibility(for: item)
            guard case .compatible(let mediaType) = compatibility else {
                return compatibility
            }
            guard mediaType == expectedMediaType else {
                return .incompatible(String(localized: "photos.error.mixed_collection"))
            }
        }
        return .compatible(expectedMediaType)
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

    @discardableResult
    func saveDownloadedFileToApplicationFolder(_ result: CompletedDownloadResult) -> Bool {
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            var appFolder = documents.appendingPathComponent("Saved", isDirectory: true)
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
            let preferences = SavedDownloadPreferences.load()
            if preferences.organizeByService {
                guard let serviceFolderName = result.serviceFolderName else {
                    throw NSError(
                        domain: "Palladium",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "post_download.error.missing_service")]
                    )
                }
                appFolder.appendPathComponent(serviceFolderName, isDirectory: true)
                try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
            }

            let shouldCreateDownloadFolder = result.isCollection || preferences.alwaysUseFolder
            appendConsoleText(
                "[palladium] save layout: service=\(preferences.organizeByService) "
                    + "always-folder=\(preferences.alwaysUseFolder) collection=\(result.isCollection)\n",
                source: .app
            )
            if shouldCreateDownloadFolder {
                let destinationFolder = uniqueDestinationURL(
                    in: appFolder,
                    preferredName: result.savedFolderName,
                    isDirectory: true
                )
                try copyItemsAtomically(result.items, to: destinationFolder, stagingParent: appFolder)
                cleanupTemporaryDownloadSource(for: result)
                alertMessage = nil
                showAlert = false
                showTemporaryToast(
                    String(
                        format: String(localized: "post_download.toast.saved_folder_name"),
                        destinationFolder.lastPathComponent
                    )
                )
                return true
            }

            if let itemURL = result.primaryMediaURL ?? result.items.first {
                let destination = uniqueDestinationURL(
                    in: appFolder,
                    preferredName: itemURL.lastPathComponent,
                    isDirectory: false
                )
                try FileManager.default.copyItem(at: itemURL, to: destination)
                cleanupTemporaryDownloadSource(for: result)
                alertMessage = nil
                showAlert = false
                showTemporaryToast(
                    String(format: String(localized: "post_download.toast.saved_folder"), destination.lastPathComponent)
                )
                return true
            } else {
                throw NSError(
                    domain: "Palladium",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "post_download.error.no_files")]
                )
            }

        } catch {
            alertMessage = String(format: String(localized: "post_download.error.save_folder"), error.localizedDescription)
            showAlert = true
            return false
        }
    }

    private func cleanupTemporaryDownloadSource(for result: CompletedDownloadResult) {
        guard result.cleansTemporarySourceAfterSave else { return }
        let temporaryRoot = try? downloadsDirectoryURL()
        let candidate = result.folderURL
            ?? result.primaryMediaURL?.deletingLastPathComponent()
            ?? result.items.first?.deletingLastPathComponent()
        guard let temporaryRoot,
              let candidate,
              candidate.path.hasPrefix(temporaryRoot.path + "/") else { return }
        try? FileManager.default.removeItem(at: candidate)
    }

    private func uniqueDestinationURL(in directory: URL, preferredName: String, isDirectory: Bool) -> URL {
        let fileManager = FileManager.default
        let sanitizedName = preferredName.isEmpty ? "Download" : preferredName
        var candidate = directory.appendingPathComponent(sanitizedName, isDirectory: isDirectory)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let url = URL(fileURLWithPath: sanitizedName)
        let baseName = url.deletingPathExtension().lastPathComponent
        let extensionName = url.pathExtension
        var index = 1
        repeat {
            let numberedName = extensionName.isEmpty
                ? "\(baseName) (\(index))"
                : "\(baseName) (\(index)).\(extensionName)"
            candidate = directory.appendingPathComponent(numberedName, isDirectory: isDirectory)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private func copyItemsAtomically(_ items: [URL], to destination: URL, stagingParent: URL) throws {
        let fileManager = FileManager.default
        let staging = stagingParent.appendingPathComponent(".palladium-save-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for itemURL in items {
                let itemDestination = uniqueDestinationURL(
                    in: staging,
                    preferredName: itemURL.lastPathComponent,
                    isDirectory: false
                )
                try fileManager.copyItem(at: itemURL, to: itemDestination)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func handlePostDownloadAction(
        _ action: PostDownloadAction,
        for result: CompletedDownloadResult,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        switch action {
        case .saveToPhotos:
            if result.isCollection {
                saveDownloadedFilesToPhotos(result.items, onSuccess: onSuccess)
                return
            }
            guard let fileURL = result.photosCandidateURL else {
                reopenDownloadActionAfterAlert = true
                alertMessage = String(localized: "photos.error.single_only")
                showAlert = true
                return
            }
            saveDownloadedFileToPhotos(fileURL, onSuccess: onSuccess)
        case .openShareSheet:
            sharePayload = SharePayload(activityItems: result.shareActivityItems)
        case .saveToApplicationFolder:
            if saveDownloadedFileToApplicationFolder(result) {
                onSuccess?()
            }
        }
    }
}

enum DownloadedMediaGroup: Int, CaseIterable {
    case image
    case video
    case audio
    case file

    private static let imageExtensions: Set<String> = [
        "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp",
    ]
    private static let videoExtensions: Set<String> = [
        "3gp", "avi", "flv", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "ts", "webm",
    ]
    private static let audioExtensions: Set<String> = [
        "aac", "aiff", "flac", "m4a", "mp3", "ogg", "opus", "wav", "weba", "wma",
    ]

    static func classify(_ url: URL) -> Self {
        let fileExtension = url.pathExtension.lowercased()
        if imageExtensions.contains(fileExtension) {
            return .image
        }
        if videoExtensions.contains(fileExtension) {
            return .video
        }
        if audioExtensions.contains(fileExtension) {
            return .audio
        }
        return .file
    }

    var supportsPhotos: Bool {
        self == .image || self == .video
    }

    var displayName: String {
        switch self {
        case .image:
            return String(localized: "post_download.group.images")
        case .video:
            return String(localized: "post_download.group.videos")
        case .audio:
            return String(localized: "post_download.group.audio")
        case .file:
            return String(localized: "post_download.group.files")
        }
    }

    var completionTitle: String {
        switch self {
        case .image:
            return String(localized: "post_download.title.images")
        case .video:
            return String(localized: "post_download.title.videos")
        case .audio:
            return String(localized: "post_download.title.audio")
        case .file:
            return String(localized: "post_download.title.files")
        }
    }
}

struct CompletedDownloadResult {
    let items: [URL]
    let primaryMediaURL: URL?
    let folderURL: URL?
    let titleHint: String?
    let sourceURL: URL?
    let mediaGroup: DownloadedMediaGroup?
    let cleansTemporarySourceAfterSave: Bool
    let id = UUID()

    init(
        items: [URL],
        primaryMediaURL: URL?,
        folderURL: URL?,
        titleHint: String?,
        sourceURL: URL?,
        mediaGroup: DownloadedMediaGroup? = nil,
        cleansTemporarySourceAfterSave: Bool = true
    ) {
        self.items = items
        self.primaryMediaURL = primaryMediaURL
        self.folderURL = folderURL
        self.titleHint = titleHint
        self.sourceURL = sourceURL
        self.mediaGroup = mediaGroup
        self.cleansTemporarySourceAfterSave = cleansTemporarySourceAfterSave
    }

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

    @MainActor
    func separatedByMediaGroup() -> [Self] {
        let groupedItems = Dictionary(grouping: items, by: DownloadedMediaGroup.classify)
        let orderedGroups = DownloadedMediaGroup.allCases.compactMap { group -> (DownloadedMediaGroup, [URL])? in
            guard let items = groupedItems[group], !items.isEmpty else { return nil }
            return (group, items)
        }
        let isMixedMedia = orderedGroups.count > 1

        return orderedGroups.map { group, groupedItems in
            let groupedPrimaryURL = primaryMediaURL.flatMap { primaryURL in
                groupedItems.contains(primaryURL) ? primaryURL : nil
            } ?? groupedItems.first
            let groupedTitleHint: String?
            if isMixedMedia, let titleHint {
                groupedTitleHint = "\(titleHint) - \(group.displayName)"
            } else {
                groupedTitleHint = titleHint
            }

            return Self(
                items: groupedItems,
                primaryMediaURL: groupedPrimaryURL,
                folderURL: folderURL,
                titleHint: groupedTitleHint,
                sourceURL: sourceURL,
                mediaGroup: group,
                cleansTemporarySourceAfterSave: !isMixedMedia
            )
        }
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

    var serviceFolderName: String? {
        sanitizedFolderName(DownloadServiceDomain.canonicalHost(for: sourceURL))
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
