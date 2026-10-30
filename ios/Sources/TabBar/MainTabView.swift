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
            // Tab 0: My Trails (Primary Home Destination - PRD v0.4.0 §3)
            MyTrailsView()
                .tabItem {
                    Label("My Trails", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .tag(0)

            // Tab 1: Discover (Shared Catalogue - PRD v0.4.0 §3 & §5)
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "globe.americas.fill")
                }
                .tag(1)

            // Tab 2: Record Action (PRD §3: Keep existing Start a trail action prominent)
            Color.clear
                .tabItem {
                    Label("Record", systemImage: "record.circle.fill")
                }
                .tag(2)

            // Tab 3: You (Local Contributor Profile & Settings)
            UserProfileView()
                .tabItem {
                    Label("You", systemImage: "person.crop.circle")
                }
                .tag(3)
        }
        .tint(AppColors.forestGreen)
        .onChange(of: selectedTab) { oldTab, newValue in
            if newValue == 2 {
                // Tapping Record opens the spatial scanner full screen
                showingRecordFullScreen = true
                // Keep the underlying navigation anchored on previous tab
                selectedTab = (oldTab == 2 ? 0 : oldTab)
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
