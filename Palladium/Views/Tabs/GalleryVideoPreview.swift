import SwiftUI
import UIKit

struct GalleryVideoPreview: View {
    let item: GalleryItem

    @State private var thumbnail: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.6), in: Circle())
                            .padding(8)
                    }
            } else if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: item.placeholderIconName)
                        .font(.system(size: 34, weight: .semibold))
                    Text(item.mediaLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .task(id: item) {
            thumbnail = nil
            isLoading = true
            let preview = await GalleryVideoThumbnailLoader.thumbnail(for: item)
            guard !Task.isCancelled else { return }
            thumbnail = preview
            isLoading = false
        }
    }
}
