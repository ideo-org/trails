//
//  MainTabView.swift
//  Trails
//
//  Primary navigation for Trails (PRD Section 7.1):
//  1. My Trails: Search, open, and manage local recordings
//  2. Record: Begin a new capture
//  3. You: Local author identity & spatial survey settings
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            MyTrailsView()
                .tabItem {
                    Label("My Trails", systemImage: "figure.walk")
                }
                .tag(0)

            NavigationStack {
                ScannerView()
            }
            .tabItem {
                Label("Record", systemImage: "record.circle")
            }
            .tag(1)

            UserProfileView()
                .tabItem {
                    Label("You", systemImage: "person.crop.circle")
                }
                .tag(2)
        }
        .tint(AppColors.forestGreen)
    }
}

#Preview {
    MainTabView()
}
