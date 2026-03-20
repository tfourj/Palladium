import SwiftUI

struct StorageSettingsView: View {
    let summary: StorageManagementSummary
    let isBusy: Bool
    let onRefresh: () -> Void
    let onClearDownloads: () -> Void
    let onClearSaved: () -> Void
    let onClearCache: () -> Void
    let onPruneDownloads: (StoragePruneWindow) -> Void
    let onPruneSaved: (StoragePruneWindow) -> Void
    let onPruneCache: (StoragePruneWindow) -> Void
    let onAppear: () -> Void

    @State private var showClearDownloadsConfirmation = false
    @State private var showClearSavedConfirmation = false

    var body: some View {
        Form {
            Section {
                summaryRow(
                    title: "Temporary Downloads",
                    subtitle: summary.downloads.locationLabel,
                    systemImage: "tray.full.fill",
                    accentColor: .blue,
                    location: summary.downloads
                )

                summaryRow(
                    title: "Saved Files",
                    subtitle: summary.saved.locationLabel,
                    systemImage: "folder.fill",
                    accentColor: .green,
                    location: summary.saved
                )

                summaryRow(
                    title: "yt-dlp Cache",
                    subtitle: summary.cache.locationLabel,
                    systemImage: "internaldrive.fill",
                    accentColor: .orange,
                    location: summary.cache
                )

                HStack {
                    Text("Total")
                    Spacer()
                    Text(summary.formattedTotalSize)
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Usage", action: onRefresh)
                    .disabled(isBusy)
            } header: {
                Text("Overview")
            } footer: {
                Text("Temporary Downloads stores active and recent run folders. Saved Files keeps copies made with Save to App Folder.")
            }

            Section {
                Button("Clear download folder", role: .destructive) {
                    showClearDownloadsConfirmation = true
                }
                .disabled(isBusy)

                Menu("Remove older than") {
                    ForEach(StoragePruneWindow.allCases) { window in
                        Button(window.title) {
                            onPruneDownloads(window)
                        }
                    }
                }
                .disabled(isBusy)
            } header: {
                Text("Temporary Downloads")
            } footer: {
                Text("This only affects Palladium's temporary download folder. Use it to remove stale run folders without touching Saved Files.")
            }

            Section {
                Button("Clear saved folder", role: .destructive) {
                    showClearSavedConfirmation = true
                }
                .disabled(isBusy)

                Menu("Remove older than") {
                    ForEach(StoragePruneWindow.allCases) { window in
                        Button(window.title) {
                            onPruneSaved(window)
                        }
                    }
                }
                .disabled(isBusy)
            } header: {
                Text("Saved Files")
            } footer: {
                Text("Saved Files contains downloads you explicitly kept. Clearing this section removes those copies from Palladium storage.")
            }

            Section {
                Button("Clear cache", role: .destructive, action: onClearCache)
                    .disabled(isBusy)

                Menu("Remove older than") {
                    ForEach(StoragePruneWindow.allCases) { window in
                        Button(window.title) {
                            onPruneCache(window)
                        }
                    }
                }
                .disabled(isBusy)
            } header: {
                Text("yt-dlp Cache")
            } footer: {
                Text("The cache stores yt-dlp metadata and web assets. Clearing it may make the next run a little slower.")
            }

            if isBusy {
                Section {
                    Text("Storage actions are disabled while a download or package task is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Download Storage")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear the temporary download folder?", isPresented: $showClearDownloadsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: onClearDownloads)
        } message: {
            Text("This removes everything in Palladium/Documents/Temp, including old run folders.")
        }
        .alert("Clear the saved folder?", isPresented: $showClearSavedConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: onClearSaved)
        } message: {
            Text("This removes everything in Palladium/Documents/Saved.")
        }
        .onAppear(perform: onAppear)
    }

    private func summaryRow(
        title: String,
        subtitle: String,
        systemImage: String,
        accentColor: Color,
        location: StorageLocationSummary
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(location.formattedSize)
                    .foregroundStyle(.primary)
                Text(location.itemDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StorageManagementSummary {
    let downloads: StorageLocationSummary
    let saved: StorageLocationSummary
    let cache: StorageLocationSummary

    static let empty = StorageManagementSummary(
        downloads: .empty(locationLabel: "Documents/Temp"),
        saved: .empty(locationLabel: "Documents/Saved"),
        cache: .empty(locationLabel: "Library/Caches/yt-dlp")
    )

    var totalBytes: Int64 {
        downloads.totalBytes + saved.totalBytes + cache.totalBytes
    }

    var formattedTotalSize: String {
        StorageLocationSummary.byteFormatter.string(fromByteCount: totalBytes)
    }
}

struct StorageLocationSummary {
    let locationLabel: String
    let itemCount: Int
    let totalBytes: Int64

    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func empty(locationLabel: String) -> StorageLocationSummary {
        StorageLocationSummary(locationLabel: locationLabel, itemCount: 0, totalBytes: 0)
    }

    var formattedSize: String {
        Self.byteFormatter.string(fromByteCount: totalBytes)
    }

    var itemDescription: String {
        "\(itemCount) item\(itemCount == 1 ? "" : "s")"
    }
}

enum StoragePruneWindow: String, CaseIterable, Identifiable {
    case oneDay
    case sevenDays
    case thirtyDays
    case ninetyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay:
            return "1 day"
        case .sevenDays:
            return "7 days"
        case .thirtyDays:
            return "30 days"
        case .ninetyDays:
            return "90 days"
        }
    }

    var cutoffDate: Date {
        let now = Date()
        switch self {
        case .oneDay:
            return now.addingTimeInterval(-86_400)
        case .sevenDays:
            return now.addingTimeInterval(-(86_400 * 7))
        case .thirtyDays:
            return now.addingTimeInterval(-(86_400 * 30))
        case .ninetyDays:
            return now.addingTimeInterval(-(86_400 * 90))
        }
    }
}
