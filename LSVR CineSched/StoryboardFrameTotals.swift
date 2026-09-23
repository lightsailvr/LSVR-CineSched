//
//  StoryboardFrameTotals.swift
//  LSVR CineSched
//
//  How many bytes of storyboard frames a project carries, and the caption the shot page
//  shows once that passes 20 MB (#41, spec #36). Frames live inside the project's JSON as
//  base64 JPEG (ADR 0007), so they are what makes a file heavy; the caption tells the
//  person adding the twentieth megabyte of boards before iCloud sync starts to feel it,
//  and says nothing below the threshold, where it would only be noise.
//
//  The sum is of the stored bytes (the JPEG, not its base64, which is a third larger in
//  the file): every scene's own frame and every shot's, across the Boneyard and the days.
//  Pure, and cheap enough to compute per presentation of an editor: it reads `Data.count`,
//  never the pixels.
//

import Foundation

extension Scene {
    /// The bytes of this scene's own frame plus every one of its shots' frames.
    nonisolated var storyboardFrameBytes: Int {
        shots.reduce(frame?.count ?? 0) { $0 + ($1.frame?.count ?? 0) }
    }
}

extension ProjectData {
    /// Every storyboard frame's bytes in the project: the Boneyard's scenes and every
    /// day's, each scene's frame and its shots'. 0 without frames.
    nonisolated var storyboardFrameBytes: Int {
        Self.storyboardFrameBytes(shootDays: shootDays, allScenes: allScenes)
    }

    /// The same over the pieces, for a view that holds the days and the Boneyard rather
    /// than the project (the Stripboard, the calendar).
    nonisolated static func storyboardFrameBytes(shootDays: [ShootDay], allScenes: [Scene]) -> Int {
        let boneyard = allScenes.reduce(0) { $0 + $1.storyboardFrameBytes }
        return shootDays.reduce(boneyard) { total, day in
            day.scenes.reduce(total) { $0 + $1.storyboardFrameBytes }
        }
    }
}

enum StoryboardFrameTotals {
    /// The total past which the shot page shows its caption: 20 MB, counted the way the
    /// caption's formatter counts (1 MB = 1,000,000 bytes, as Finder shows file sizes).
    static let captionThreshold = 20_000_000

    /// "Storyboard frames: 24 MB" for a total past `captionThreshold`, nil at or below it.
    static func caption(forBytes bytes: Int) -> String? {
        guard bytes > captionThreshold else { return nil }
        return String(format: L("Storyboard frames: %@"), formatter.string(fromByteCount: Int64(bytes)))
    }

    /// Built once (#34: nothing a body draws builds a formatter).
    private static let formatter: ByteCountFormatter = {
        let formatter          = ByteCountFormatter()
        formatter.countStyle   = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter
    }()
}

// MARK: - The editor's view of the total

extension SceneDraft {
    /// The bytes of the frames this draft holds: the scene's frame and every shot's.
    var storyboardFrameBytes: Int {
        shots.reduce(frame?.count ?? 0) { $0 + ($1.frame?.count ?? 0) }
    }
}

extension StoryboardFrameTotals {
    /// The project's total as the open editor would leave it: `projectBytes` (the total
    /// when the editor was presented) with `saved`'s frames replaced by `draft`'s, so a
    /// frame added or removed before Save moves the caption at once. Never below 0.
    static func bytes(inProject projectBytes: Int, replacing saved: Scene, with draft: SceneDraft) -> Int {
        max(0, projectBytes - saved.storyboardFrameBytes + draft.storyboardFrameBytes)
    }
}
