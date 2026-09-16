// PlatformPlaceholderView.swift
// Platform seam: the root view on iOS, iPadOS and visionOS while the port is in progress
// (milestone 1 of #1). It exists so each platform has a running target from day one;
// the real iPad editor and iPhone companion replace it in milestones 3 and 4. Never
// built for the Mac, which keeps ContentView as its root.

#if !os(macOS)
import SwiftUI
import UIKit

struct PlatformPlaceholderView: View {
    private var platformName: String {
        #if os(visionOS)
        return "visionOS"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("CineSched")
                .font(.largeTitle.bold())
            Text(String(format: L("CineSched for %@ is in progress."), platformName))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
