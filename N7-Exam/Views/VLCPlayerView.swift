//
//  VLCPlayerView.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import SwiftUI
import VLCKitSPM

struct VLCPlayerView: UIViewRepresentable {
    let player: VLCMediaPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        player.drawable = view
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        player.drawable = uiView
    }
}
