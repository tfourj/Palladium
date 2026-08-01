# Download safety and gallery handling

This branch changes only the download and post-download pipeline. It does not
contain service-specific names or rules tied to a named website.

## Saved files

- Existing files and folders are never silently replaced. A collision produces
  `Name (1)`, `Name (2)`, and so on, preserving the file extension.
- **Always create a folder** wraps a single downloaded item in its own folder.
- **Organize by service** creates a parent folder from the source hostname after
  removing `www.` and characters that are unsafe in a folder name.
- The two options are independent and apply only when saving into Palladium's
  `Saved` directory.
- **Organize by service** changes only the parent directory. Collections still
  receive a uniquely named download folder; single items stay directly in the
  service directory unless **Always create a folder** is also enabled.
- When both options are enabled, the layout is
  `Saved/<service>/<unique download folder>/<media>` for both collections and
  single items.
- Collection folders are assembled from the selected media only and published
  atomically after every copy succeeds. Repeated collections become `Name (1)`,
  `Name (2)`, and so on; equal filenames inside one collection are numbered too.
- A successful copy removes the associated temporary `run-*` download folder.
  Failed copies leave the temporary source intact so data is not lost.

## Gallery and video selection

- Gallery mode preserves both real images and videos selected by the user.
- Every gallery resolver/download closes its SQLite cache connection, removes
  gallery-dl module state, and finalizes stale sessions before returning. The
  same URL can therefore be resolved and downloaded again in the same app
  session as a completely new job.
- Video mode filters album-style embedded playlists during the single yt-dlp
  extraction pass. Image entries and repeated media URLs are removed before
  media transfer starts, so progress counts match the distinct videos without a
  second metadata/network pass.
- Duplicate detection also runs after each embedded entry has been fully
  resolved. This covers extractors whose preliminary playlist entries look
  different but ultimately resolve to the same CDN media URL.
- Multiple distinct videos remain selected. For example, two videos plus one
  image result in two video downloads in video mode; gallery mode can retain all
  three selected media.
- A SHA-256 comparison after download removes byte-identical output files as a
  final safety net. This is not the primary fix: filtering happens before the
  actual download whenever playlist metadata permits it.

## User-interface cleanup

- Gallery downloads use the same progress card as video playlists, including
  total, completed, failed, current-item, cancellation, and final state.
- Gallery progress comes from structured start/completion/failure events emitted
  by the downloader job, rather than inferred console paths.
- The format-selection chevron is hidden for image/gallery mode, where it does
  not represent an available action.
- Structured gallery failures expose the useful final error instead of a generic
  Python exception.
- Notification diagnostics are emitted once to the Xcode console.

## Verification

- Python modules compile with `python3 -m py_compile`.
- `git diff --check` reports no whitespace errors.
- The app builds successfully with Xcode Beta for an iPhone 17 Pro simulator
  running iOS 27.0, including the embedded Python runtime and local Swift
  packages.
