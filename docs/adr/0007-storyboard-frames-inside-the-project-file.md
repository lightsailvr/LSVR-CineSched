# 0007 — Storyboard frames inside the project file (amends ADR 0001)

Status: Accepted (2026-09-23, #37, part of #36). Amends 0001: the format stays one JSON
document evolved by additive optional fields; its "no binary encoding" clause gains one
exception, image bytes as base64 strings.

## Context

Shot lists (#36) give every shot, and a scene with no shots, one optional storyboard
frame: an image the director draws or photographs. The frame has to travel wherever the
project does: autosave, iCloud Drive sync, conflict versions and Restore Other Version
(ADR 0004, #15), Duplicate, Revert To, and Copy and Paste of scenes between projects (#22).

A `.cinesched` file is one flat JSON document (ADR 0001, ADR 0005) and the type conforms
to JSON, not to a package. No image bytes were stored anywhere before. The alternatives:

- **A package** (a folder with the JSON and one image file per frame). Every existing path
  would need to change: the document's reader and writer, the type's conformance (ADR
  0005), the legacy `.json` handoff, the conflict resolution that reads and compares
  whole versions, the clipboard that carries scenes by value. Two ADRs would be
  superseded for one feature.
- **Frames beside the file** (a sidecar folder, or iCloud's container). They would not
  travel with Duplicate, Move To, AirDrop or a conflict version, and could be orphaned.
- **Frames inside the JSON**, as base64 strings. Every path above keeps working untouched,
  because a frame is just another field of the scene value.

## Decision

- A frame is `Data` on the model (`Shot.frame`, `Scene.frame`), JPEG bytes, and the file
  carries it as the JSON encoder's default: a base64 string (the encoder escapes the
  alphabet's `/` as `\/`). Both fields are optional with `decodeIfPresent` defaults, so
  older files open and older builds ignore them (ADR 0001).
- Frames are **downscaled at import**: every source (paste, drop, Photos, the camera, a
  file) decodes the image and passes it through one pure function that scales the long
  edge down to at most 1200 px and encodes JPEG at a fixed quality (#38). A 1200 px frame
  is about 100–200 KB; the original photo is never stored.
- The shot page shows the project's **total frame size** as a caption once it passes
  20 MB, so the user knows the file is getting heavy before sync slows down (#39).
- The project file is written with **sorted keys**. Without them the encoder wrote each
  object's keys in an order that changed from save to save, so an unchanged project never
  saved to the same bytes twice; with frames the file is large and iCloud uploads it
  whole, and identical bytes for an identical project is the least it should do.
- A scene with no shots and no frame writes neither key, so a project without shot lists
  keeps the same content on its next save.

## Consequences

- File size grows with the frames: a hundred frames at about 100 KB is about 13 MB of
  base64, rewritten on every autosave and uploaded whole by iCloud. The caption and the
  downscale are the mitigation; the package format is the future path, recorded as #44
  (`needs-triage`), to be taken when real projects outgrow this.
- Undo snapshots hold whole project values. Frame bytes are copy-on-write `Data`, so the
  snapshots share one buffer per frame until a frame is replaced; every snapshot in the
  undo stack keeps its frames alive until the stack is trimmed.
- `Scene` is `Hashable` and `Equatable`, so comparing or hashing scenes now touches frame
  bytes (equality can short-circuit on shared storage; hashing cannot). Code that puts
  scenes in hot `Set`s or dictionary keys should key them by id.
- Other CineSched lineages read the file as before and ignore `shots` and `frame`; saving
  from them drops both.
