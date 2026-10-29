//
//  MainTabView.swift
//  Trails
//
//  Primary navigation for Trails (PRD v0.1.0 Section 7.1):
//  1. My Trails: Search, open, and manage local recordings
//  2. Record: Begin a new spatial capture (central action)
//  3. You: Local author identity & spatial survey settings
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @State private var showingRecordFullScreen: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: My Trails (Primary Home Destination - PRD §7.1 & §8.1)
            MyTrailsView()
                .tabItem {
                    Label("My Trails", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .tag(0)

            // Tab 1: Record Action (PRD §7.1 & §8.2)
            Color.clear
                .tabItem {
                    Label("Record", systemImage: "record.circle.fill")
                }
                .tag(1)

            // Tab 2: You (Local Contributor Profile - PRD §7.1 & §9.1)
            UserProfileView()
                .tabItem {
                    Label("You", systemImage: "person.crop.circle")
                }
                .tag(2)
        }
        .tint(AppColors.forestGreen)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 {
                // Tapping Record opens the spatial scanner full screen
                showingRecordFullScreen = true
                // Keep the underlying navigation anchored on My Trails
                selectedTab = 0
            }
        }
        .fullScreenCover(isPresented: $showingRecordFullScreen) {
            ScannerView()
        }
    }
}

#Preview {
    MainTabView()
}
