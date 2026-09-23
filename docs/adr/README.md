# Architecture Decision Records

One file per decision, numbered: `NNNN-short-slug.md`. Status is one of Proposed, Accepted,
Superseded (by NNNN), or Deprecated. Keep each ADR short: context, decision, consequences.

The first ADRs record decisions inherited from the codebase as found on 2026-09-02, so that future
work has something explicit to contradict or reaffirm.

## Index

- [0001](0001-json-project-files-with-additive-codable-defaults.md) — Project files are plain JSON, evolved by additive optional fields (amended by 0005, 0007)
- [0002](0002-no-third-party-dependencies.md) — No third-party dependencies
- [0003](0003-one-multiplatform-target-with-platform-seams.md) — One multiplatform target with explicit platform seams
- [0004](0004-one-project-document-on-every-platform.md) — One project document on every platform
- [0005](0005-native-cinesched-file-type.md) — A native `.cinesched` file type
- [0006](0006-icloud-folder-owned-by-the-ios-app.md) — The CineSched iCloud folder is owned by the iOS app; the Mac stays entitlement-free
- [0007](0007-storyboard-frames-inside-the-project-file.md) — Storyboard frames inside the project file
