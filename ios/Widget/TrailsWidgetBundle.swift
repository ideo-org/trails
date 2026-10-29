//
//  TrailsWidgetBundle.swift
//  TrailsWidget
//
//  Widget extension entry point for home screen and lock screen widgets.
//

import WidgetKit
import SwiftUI

@main
struct TrailsWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()           // Home screen widget (small, medium)
        LockScreenStreakWidget() // Lock screen widgets (circular, inline, rectangular)
    }
}
