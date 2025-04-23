//
//  VideoPlayerVM+Extensions.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import Foundation
import VLCKitSPM

extension VideoPlayerViewModel {
    
    // 加载外部字幕文件
    func loadSubtitle(from url: URL) {
        guard let player = player, let media = player.media else {
            print("无法加载字幕：播放器或媒体未初始化")
            return
        }
    
        print("尝试加载字幕: \(url.lastPathComponent)")
    
        // 添加字幕文件
        media.addOption("sub-file=\(url.path)")
        let result = player.addPlaybackSlave(url, type: .subtitle, enforce: true)
        print("字幕加载\(result == 0 ? "成功" : "失败")")
    
        // 给VLC一些时间来处理字幕文件
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                updateSubtitleStatus()
            }
        }
    }
    
    // 更新字幕状态
    private func updateSubtitleStatus() {
        guard let player = player else { return }
        
        let trackIndex = player.currentVideoSubTitleIndex
        let trackCount = player.numberOfSubtitlesTracks
        
        print("字幕轨道状态 - 索引: \(trackIndex), 总数: \(trackCount)")
        
        if trackCount > 0 {
            // 如果没有激活字幕轨道，则激活第一个
            if trackIndex < 0 {
                player.currentVideoSubTitleIndex = 0
                print("已激活第一个字幕轨道")
            }
            
            // 更新UI状态
            self.subtitleEnabled = true
            self.subtitleDelay = 0
            player.currentVideoSubTitleDelay = 0
            print("字幕已成功加载和激活")
        } else {
            print("未检测到字幕轨道")
        }
    }
    
    // 调整字幕延迟（正值表示字幕延迟显示，负值表示字幕提前显示）
    func adjustSubtitleDelay(seconds: TimeInterval) {
        guard let player = player, subtitleEnabled, player.currentVideoSubTitleIndex >= 0 else { 
            print("调整字幕延迟失败：播放器未初始化或字幕未激活")
            return 
        }
        
        // 计算新的延迟值并检查限制
        let newDelay = subtitleDelay + seconds
        if newDelay > 30 {
            print("字幕延迟已达到最大值 30 秒")
            return
        } else if newDelay < -30 {
            print("字幕提前已达到最大值 -30 秒")
            return
        }
        
        // 保存当前位置
        let currentPosition = player.time
        
        // 设置新的字幕延迟（VLC使用微秒作为单位）
        let delayInMicroseconds = Int(newDelay * 1000000)
        player.currentVideoSubTitleDelay = delayInMicroseconds
        
        // 恢复播放位置并更新状态
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                player.time = currentPosition
                subtitleDelay = newDelay
                print("字幕延迟已调整到: \(newDelay) 秒")
            }
        }
    }
    
    // 字幕相关便捷方法
    func resetSubtitleDelay() {
        guard let player = player, subtitleEnabled, player.currentVideoSubTitleIndex >= 0 else { 
            print("重置字幕延迟失败：字幕未激活")
            return
        }
        
        player.currentVideoSubTitleDelay = 0
        
        Task {
            await MainActor.run {
                subtitleDelay = 0
                print("字幕延迟已重置")
            }
        }
    }
    
    // 字幕提前显示
    func subtitleForward(seconds: TimeInterval) {
        adjustSubtitleDelay(seconds: -seconds) // 负值表示字幕提前显示
    }
    
    // 字幕延迟显示
    func subtitleBackward(seconds: TimeInterval) {
        adjustSubtitleDelay(seconds: seconds) // 正值表示字幕延迟显示
    }

    // 禁用字幕
    func disableSubtitle() {
        guard let player = player else { return }
        
        if player.currentVideoSubTitleIndex >= 0 {
            player.currentVideoSubTitleIndex = -1
        }
        
        Task {
            await MainActor.run {
                subtitleEnabled = false
                subtitleDelay = 0
                print("字幕已禁用")
            }
        }
    }
}
