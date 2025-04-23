//
//  Formatters.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import Foundation

// 格式化时间为 HH:MM:SS 格式
func formatTime(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = Int(time) / 60 % 60
    let seconds = Int(time) % 60
    
    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
