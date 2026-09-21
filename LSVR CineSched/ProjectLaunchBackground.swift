// ProjectLaunchBackground.swift
// The launch screen's backdrop on iOS and visionOS (#12): what `CineSchedApp`'s
// `DocumentGroupLaunchScene` draws behind the title, New Project, the imports and the
// recents. Lived in MinimalProjectEditor.swift until the iPhone editor replaced that
// view (#24). Platform-free SwiftUI: the Mac compiles it and never shows it.

import SwiftUI

/// The accent color and the app's film-stack symbol, kept quiet so the system's controls
/// read over it.
struct ProjectLaunchBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "film.stack")
                .font(.system(size: 220, weight: .thin))
                .foregroundStyle(.white.opacity(0.18))
                .padding(.top, 48)
                .padding(.trailing, -40)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}
