# 0001 — Project files are plain JSON, evolved by additive optional fields

Status: Accepted (inherited, recorded 2026-09-02). Amended by 0005 (2026-09-16): the format
stands; the "no custom UTI" clause is reversed by the native `.cinesched` type.

## Context

CineSched saves a whole project as one human-readable `.json` file (`ProjectData` in `Models.swift`).
Files from all three lineages of the app (original, alucardGonza fork, LSVR version) must keep
opening in each other, and a future cross-platform client should be able to read them.

## Decision

- Keep the format as pretty-printed JSON with ISO-8601 dates, no custom UTI, no binary encoding.
- There is no schema version number. Compatibility is achieved by every `Codable` type having a
  hand-written `init(from:)` that uses `decodeIfPresent(...) ?? default` for any field added after
  the original shape. New fields are always optional-with-default and never renamed.
- Legacy raw values (e.g. Spanish `BannerType` cases) are mapped in decoders rather than migrated on disk.

## Consequences

- Adding a model field is a two-line change (CodingKeys + decoder default) and old files keep working.
- Removing or renaming a field is a breaking change and needs a real migration plan, which would be
  the point to introduce a version field. Until then, do not add one speculatively.
