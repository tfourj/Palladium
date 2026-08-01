enum TemporaryDownloadRetentionPolicy {
    static func shouldRemoveSource(
        showsTemporaryDownloads: Bool,
        resultAllowsCleanup: Bool
    ) -> Bool {
        resultAllowsCleanup && !showsTemporaryDownloads
    }
}
