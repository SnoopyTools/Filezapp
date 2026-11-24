# Filez

A modern iOS 18 file manager — a cleaner take on the classic Filza workflow.

Ships **sandbox-only**: it browses and edits everything the app is allowed to
reach, and shows "Permission denied" for anything outside that. Root access is
a separate, drop-in layer (see below) that Filez itself contains none of.

## Features (v1)
- Browse, sort (name/size/date/kind) and search any reachable folder
- Standard locations and your own bookmarks
- New folder / new file, rename, copy, move, delete, multi-select
- File properties: size, dates, owner/group, POSIX permissions (view + edit)
- Text editor, read-only hex viewer, plist outline + "edit as XML"
- Quick Look preview for images, PDFs, Office docs, audio and video
- Zip extract (`.zip`, `.ipa`) and compress to zip — works via any backend

## The root seam
Every privileged file operation goes through the `RootBackend` protocol in
`RootBackend.swift`. The shipped build registers `UnavailableRootBackend`, so
Filez never attempts anything it isn't permitted to.

To add root access, copy `MyRootBackend.swift.example` to `MyRootBackend.swift`,
implement the primitives with your own mechanism, and set
`RootBackendRegistry.active = MyRootBackend()` at launch. The entire UI already
runs on top of that protocol, so the moment `isAvailable` returns true the whole
filesystem opens up. No other file needs changing.

## Build
GitHub Actions builds an unsigned IPA on every push and attaches it to the
`latest` release. Install with LiveContainer. Requires iOS 18+.
(ZIPFoundation is pulled in via Swift Package Manager during the build.)

## Not in v1 yet
WebDAV / built-in web server, SMB / FTP / cloud shares, `.deb` / `.ipa`
installation, and in-place hex editing — clean follow-ups on top of the same
`FileAccess` interface.
