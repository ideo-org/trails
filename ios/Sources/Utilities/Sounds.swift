//
//  Sounds.swift
//  Trails
//
//  Created by Claude on 2024-04-16.
//

import AudioToolbox

struct Sounds {
    static func playShutterSound() {
        AudioServicesPlaySystemSound(1108)
    }
}
