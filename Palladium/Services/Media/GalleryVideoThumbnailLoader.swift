import AVFoundation
import ImageIO
import UIKit

@MainActor
enum GalleryVideoThumbnailLoader {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func thumbnail(for item: GalleryItem) async -> UIImage? {
        guard item.mediaType == .video, !Task.isCancelled else { return nil }
        let key = "\(item.url)\n\(item.thumbnailURL ?? "")" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        var image: UIImage?
        if let url = remoteURL(item.thumbnailURL) {
            image = await downloadThumbnail(url)
        }
        if image == nil, !Task.isCancelled, let url = remoteURL(item.url) {
            image = await videoFrame(url)
        }
        guard let image, !Task.isCancelled else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func remoteURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private static func downloadThumbnail(_ url: URL) async -> UIImage? {
        do {
            let request = URLRequest(url: url, timeoutInterval: 12)
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 480
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    private static func videoFrame(_ url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)

        // A stalled or protected remote video must not leave the picker spinning indefinitely.
        let timeout = Task {
            try await Task.sleep(for: .seconds(12))
            generator.cancelAllCGImageGeneration()
        }
        defer { timeout.cancel() }

        return await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let result = try await generator.image(at: .zero)
                try Task.checkCancellation()
                return UIImage(cgImage: result.image)
            } catch {
                return nil
            }
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
    }
}
