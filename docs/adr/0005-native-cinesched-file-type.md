# 0005 — A native `.cinesched` file type (amends ADR 0001)

Status: Accepted (2026-09-16, #7, part of #1). Amends 0001: the format decision stands;
the "no custom UTI" clause is reversed.

## Context

ADR 0001 chose plain JSON with no custom UTI so that files from every CineSched lineage
keep opening in each other. That worked while the only client was a Mac app with an open
panel: the app declared nothing, and a `.json` was a project because the user said so.

A document-based app (ADR 0004) has to declare what it opens and writes. On iOS and
visionOS, declaring public JSON as an editable document type makes the Files app present
every `.json` on the device as a CineSched document (#1, story 12) and gives the document
browser nothing to bind an icon, a kind name or open-in-place to. On the Mac the same
declaration would have CineSched claim every JSON in Finder.

## Decision

- Declare an exported type `com.lsvr.cinesched.project`, kind "CineSched Project",
  filename extension `cinesched`, conforming to `public.json`. `UTType.cineschedProject`
  is the Swift handle.
- The **format is unchanged**: a `.cinesched` file is byte-for-byte the JSON the app
  writes today, evolved exactly as ADR 0001 says (additive optional fields, no schema
  version). Conforming to JSON records that fact in the type system.
- It is the only type the project document writes. `.json` stays readable (ADR 0004) so
  a legacy file opens; on the Mac its first Save asks for a `.cinesched` destination,
  and on iOS and visionOS a legacy file is imported into a new `.cinesched` (both in the
  next ticket). Originals are never modified.
- The declaration lives in `Config/Info.plist`, a partial plist that Xcode merges into
  the generated one (`GENERATE_INFOPLIST_FILE` stays on; `INFOPLIST_FILE` points at it).
  It sits outside `LSVR CineSched/` because that folder is a synchronized group and a
  plist inside it would be bundled as a resource and collide with the generated plist in
  the flat iOS bundle. Only keys that cannot be expressed as `INFOPLIST_KEY_` build
  settings go there; today that is the exported type, and the next ticket adds the
  document types and the iCloud container to the same file.

## Consequences

- Other CineSched lineages open a `.cinesched` only after renaming it to `.json`. That is
  a rename, not a conversion, and is the price of the Files app showing only schedules.
- The Mac's Finder shows `.cinesched` files with the app's kind name and, once the
  document types are declared, its icon.
- A test asserts that the type resolves at runtime (`UTType("com.lsvr.cinesched.project")`
  is non-nil, so the bundle really declares it) and conforms to JSON, on every platform
  the suite runs on.
- ADR 0001's compatibility rule for the *contents* of the file is untouched; anyone
  adding a field still adds a `CodingKeys` case and a `decodeIfPresent ?? default`.
