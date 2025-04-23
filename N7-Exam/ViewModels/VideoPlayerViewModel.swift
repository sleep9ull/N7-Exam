//
//  VideoPlayerViewModel.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import Foundation
import VLCKitSPM

class VideoPlayerViewModel: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var errorMessage: String?
    @Published var isLoading = false
    
    // 简化字幕相关状态
    @Published var subtitleEnabled = false
    @Published var subtitleDelay: TimeInterval = 0
    
    var subtitleDelayTask: Task<Void, Error>? = nil
    var lastSubtitleAdjustTime: Date = Date.distantPast

    var player: VLCMediaPlayer?
    private var updateTask: Task<Void, Never>?

    func cleanup() {
        // 取消所有正在运行的任务
        updateTask?.cancel()
        updateTask = nil
        
        // 重置字幕状态
        Task {
            await MainActor.run {
                subtitleEnabled = false
                subtitleDelay = 0
            }
        }
        
        // 停止播放器并释放
        player?.stop()
        player = nil
    }

    func loadVideo(from url: URL) async {
        print("开始加载视频: \(url.path)")
        print("完整 URL: \(url.absoluteString)")
        
        await MainActor.run {
            isLoading = true // 设置加载状态
            currentTime = 0
            duration = 0
            isPlaying = false
            playbackSpeed = 1.0
            errorMessage = nil
        }
        
        cleanup()
        
        // 检查 URL 类型
        let isNetworkURL = url.scheme != "file" && url.scheme != nil
        
        // 如果是本地文件，验证文件
        if !isNetworkURL {
            if !FileManager.default.fileExists(atPath: url.path) {
                await MainActor.run {
                    errorMessage = "文件不存在: \(url.path)"
                    isLoading = false
                }
                return
            }
            
            // 检查文件大小
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[FileAttributeKey.size] as? UInt64 {
                    print("文件大小: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
                    if fileSize == 0 {
                        await MainActor.run {
                            errorMessage = "文件大小为0，可能下载不完整"
                            isLoading = false
                        }
                        return
                    }
                }
            } catch {
                print("无法获取文件信息: \(error)")
            }
        } else {
            print("使用网络URL: \(url.absoluteString)，跳过本地文件检查")
        }
        
        // 创建并配置媒体对象
        let media = VLCMedia(url: url)
        media.delegate = self
        
        // 硬件加速和缓存
        media.addOption(":hwdec=auto-copy")  // 使用自动复制模式的硬件解码，性能更好
        media.addOption(":network-caching=5000")  // 增加网络缓存到5000毫秒
        media.addOption(":file-caching=5000")  // 增加文件缓存到5000毫秒
        media.addOption(":clock-jitter=0")  // 减少时钟抖动
        media.addOption(":clock-synchro=0")  // 禁用时钟同步以提高性能
        media.addOption(":sout-mux-caching=5000") // 增加复用缓存
        
        let fileExt = url.pathExtension.lowercased()
        print("文件类型: \(fileExt)")
        
        // MKV文件，特殊处理
        if fileExt == "mkv" {
            print("为MKV文件添加特殊配置")

            media.addOption(":demux=avformat")  // 使用 avformat 解复用器
            media.addOption(":avformat-format=matroska")  // 指定 matroska 格式
            
            // 添加提高定位精度的选项
            media.addOption(":input-fast-seek")  // 启用快速定位
            media.addOption(":input-repeat=none")  // 禁用重复播放
            media.addOption(":avformat-skip-idx=0")  // 不跳过索引
            media.addOption(":avformat-analyzeduration=200000")  // 增加分析时间
            media.addOption(":avformat-keyframe-seek=1")  // 启用关键帧定位
            media.addOption(":avformat-seekable=1")  // 确保可定位
            
            // 提高解码性能的选项
            media.addOption(":codec=all")  // 使用所有可用编解码器
            media.addOption(":sout-avformat-strict=-2")  // 使用非严格模式
        }
        
        // 解析媒体以获取准确的时长和元数据
        print("开始解析媒体...")
        media.parse(options: [.parseNetwork])
        
        // 创建播放器
        print("创建播放器...")
        player = VLCMediaPlayer()
        
        // 设置播放器选项
        player?.drawable = nil // 确保没有预先分配视图
        player?.media = media
        player?.delegate = self
        
        // 等待解析媒体（增加等待时间）
        print("等待媒体解析...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)  // 增加到2秒，给SMB文件更多解析时间
        
        let durationValue = TimeInterval(truncating: player?.media?.length.value ?? 0) / 1000
        print("视频时长: \(durationValue)秒")
        
        // 如果无法获取时长，尝试额外的解析
        if durationValue <= 0 {
            print("无法获取视频时长，尝试额外解析...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // 再次尝试获取时长
            let retryDuration = TimeInterval(truncating: player?.media?.length.value ?? 0) / 1000
            print("重试后视频时长: \(retryDuration)秒")
        }
        
        await MainActor.run {
            duration = durationValue > 0 ? durationValue : 0
            isLoading = false
            
            // 自动开始播放
            player?.play()
            isPlaying = true
        }
        
        await updatePlaybackState()
    }
    
    // 播放/暂停
    func playPause() {
        guard let player = player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying = player.isPlaying
    }
    
    // 快进
    func setForward(seconds: TimeInterval) {
        guard let player = player else { return }
        
        let wasPlaying = player.isPlaying
        
        let newTime = currentTime + seconds
        let targetTime = min(newTime, duration)
        
        // 暂停状态
        if !wasPlaying {
            player.time = VLCTime(int: Int32(targetTime * 1000))
            currentTime = targetTime
            
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                await MainActor.run {
                    if !wasPlaying && player.isPlaying {
                        player.pause()
                    }
                }
            }
        } else {
            // 播放状态
            player.time = VLCTime(int: Int32(targetTime * 1000))
            currentTime = targetTime
        }
    }
    
    // 快退
    func setBackward(seconds: TimeInterval) {
        guard let player = player else { return }
        
        let wasPlaying = player.isPlaying
        
        let newTime = currentTime - seconds
        let targetTime = max(newTime, 0)
        
        // 暂停状态
        if !wasPlaying {
            player.time = VLCTime(int: Int32(targetTime * 1000))
            currentTime = targetTime
            
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                await MainActor.run {
                    if !wasPlaying && player.isPlaying {
                        player.pause()
                    }
                }
            }
        } else {
            // 播放状态
            player.time = VLCTime(int: Int32(targetTime * 1000))
            currentTime = targetTime
        }
    }
    
    // 设置播放速度
    func setPlaybackSpeed(_ speed: Float) {
        guard let player = player else { return }
        player.rate = speed
        playbackSpeed = speed
    }
    
    // 跳转到指定时间
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        player.time = VLCTime(int: Int32(time * 1000))
        currentTime = time
    }
    
    // 更新播放状态
    private func updatePlaybackState() async {
        guard let currentPlayer = player else { return }
        
        let playerReference = currentPlayer
        
        // 持续更新播放状态
        updateTask = Task {
            while !Task.isCancelled && playerReference.media != nil {
                guard player === playerReference else { break }
                
                await MainActor.run {
                    self.currentTime = TimeInterval(truncating: playerReference.time.value ?? 0) / 1000
                    self.isPlaying = playerReference.isPlaying
                    
                    // 检查播放器状态
                    if playerReference.state == .error {
                        self.errorMessage = "播放器错误: \(playerReference.media?.url?.path ?? "未知")"
                        print("播放器错误状态: \(playerReference.state.rawValue)")
                    }
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

extension VideoPlayerViewModel: VLCMediaPlayerDelegate {
    // 当播放器状态发生变化时调用
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = player else { return }
        let state = player.state
        print("播放器状态变更: \(state.rawValue)")
        
        Task { @MainActor in
            switch state {
            case .error:
                errorMessage = "播放错误"
                isLoading = false
            case .playing:
                isLoading = false
                isPlaying = true
                await updatePlaybackState()
            case .paused, .stopped, .ended:
                isLoading = false
                isPlaying = false
            default:
                break
            }
        }
    }
    
    // 添加缓冲进度回调
    func mediaPlayerBuffering(_ aNotification: Notification) {
        if let buffering = aNotification.userInfo?["VLCMediaPlayerBufferFill"] as? Float, buffering > 0.9 {
            Task { @MainActor in
                isLoading = false
            }
        }
    }
}

extension VideoPlayerViewModel: VLCMediaDelegate {
    // 当媒体元数据发生变化时调用
    func mediaMetaDataDidChange(_ aMedia: VLCMedia) {
        Task { @MainActor in
            if let duration = player?.media?.length.value {
                self.duration = TimeInterval(truncating: duration) / 1000
            }
        }
    }
    
    // 当媒体解析完成时调用，此时可获取完整媒体信息
    func mediaDidFinishParsing(_ aMedia: VLCMedia) {
        Task { @MainActor in
            if let duration = player?.media?.length.value {
                self.duration = TimeInterval(truncating: duration) / 1000
                print("解析完成，时长: \(self.duration)秒")
            }
            player?.play()
            isPlaying = true
        }
    }
}
