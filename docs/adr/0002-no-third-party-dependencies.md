# 0002 — No third-party dependencies

Status: Accepted (inherited, recorded 2026-09-02)

## Context

The app reads Highland archives (zip), parses Final Draft XML and Fountain text, and renders six
kinds of PDF. All of these have popular open-source packages.

## Decision

Use only Apple system frameworks. Zip reading is hand-rolled on `Compression` (raw DEFLATE), XML
uses `XMLParser`, and PDFs are drawn with CoreGraphics plus CoreText (originally AppKit text; see
the note below). No Swift Package Manager dependencies, CocoaPods, or Carthage.

## Consequences

- Builds are hermetic and the GPL-v3 licensing story stays simple.
- Exporters duplicate small drawing helpers (`drawText`, `drawCell`, page constants). A shared
  in-repo PDF drawing helper is the right fix, not a package. *Update 2026-09-16 (#4):* that
  helper is `PDFCanvas.swift` (CoreGraphics + CoreText, no AppKit); four exporters are on it
  (#4, #5) and the last two migrate per the exporter tickets under #1.
- Reopen this decision only if a system framework genuinely cannot do the job.
