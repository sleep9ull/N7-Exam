//
//  ContentView.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/20.
//

import SwiftUI
import VLCKitSPM

struct ContentView: View {
    @StateObject private var viewModel = VideoPlayerViewModel()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var smbViewModel = SMBViewModel()
    
    // Sheet Management
    @State private var showingFilePicker = false
    @State private var showingSMBPicker = false
    @State private var showingSMBBrowser = false
    @State private var showingSMBDownload = false
    @State private var showingSubtitleControls = false
    
    // State Management
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    
    var body: some View {
        ZStack {
            if let player = viewModel.player {
                VStack(spacing: 20) {
                    
                    Spacer()
                    
                    // 视频播放区域
                    ZStack {
                        videoPlayerView(player: player)
                        
                        // 显示加载指示器
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle())
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 80, height: 80)
                                )
                        }
                    }
                    
                    // 进度条
                    progressBarView
                    
                    // 播放控制
                    playbackControlsView
                    
                    // 功能按钮行
                    functionButtonsView
                    
                    Spacer()
                    
                    // 返回起始页面
                    backToHomeView
                    
                }
            } else {
                emptyView
            }
            
            // 显示错误信息
            if let error = viewModel.errorMessage {
                errorView(message: error)
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker(fileExtensions: ["mov", "mp4", "mkv"]) { url in
                Task {
                    await viewModel.loadVideo(from: url)
                }
            }
        }
        .sheet(isPresented: $showingSMBBrowser) {
            SMBBrowserView(
                viewModel: smbViewModel,
                playerViewModel: viewModel,
                downloadManager: downloadManager
            )
        }
        .sheet(isPresented: $showingSubtitleControls) {
            SubtitleControlView(viewModel: viewModel)
                .presentationDetents([.height(250)])
        }
    }
    
    // MARK: - View Components
    
    // 视频播放区域
    private func videoPlayerView(player: VLCMediaPlayer) -> some View {
        VLCPlayerView(player: player)
            .aspectRatio(16/9, contentMode: .fit)
            .gesture(
                TapGesture()
                    .onEnded { _ in
                        viewModel.playPause()
                    }
            )
    }
    
    // 进度条
    private var progressBarView: some View {
        HStack {
            Text(formatTime(viewModel.currentTime))
                .font(.caption)
            
            Slider(value: Binding(
                get: { viewModel.currentTime },
                set: { viewModel.seek(to: $0) }
            ), in: 0...max(1, viewModel.duration))
            .controlSize(.small)
            
            Text(formatTime(viewModel.duration))
                .font(.caption)
        }
        .padding(.horizontal)
    }
    
    // 播放控制按钮
    private var playbackControlsView: some View {
        HStack(spacing: 30) {
            // 后退按钮
            Button(action: {
                viewModel.setBackward(seconds: 10)
            }) {
                Image(systemName: "gobackward.10")
                    .font(.title)
            }
            
            // 播放/暂停按钮
            Button(action: {
                viewModel.playPause()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 50))
            }
            
            // 前进按钮
            Button(action: {
                viewModel.setForward(seconds: 10)
            }) {
                Image(systemName: "goforward.10")
                    .font(.title)
            }
        }
    }
    
    // 功能按钮
    private var functionButtonsView: some View {
        HStack(spacing: 20) {
            // 速度控制
            Menu {
                Button("0.5x") { viewModel.setPlaybackSpeed(0.5) }
                Button("1.0x") { viewModel.setPlaybackSpeed(1.0) }
                Button("1.5x") { viewModel.setPlaybackSpeed(1.5) }
                Button("2.0x") { viewModel.setPlaybackSpeed(2.0) }
            } label: {
                HStack {
                    Image(systemName: "speedometer")
                    Text("\(String(format: "%.2f", viewModel.playbackSpeed))x")
                }
                .padding(15)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            
            // 字幕控制按钮
            Button(action: {
                showingSubtitleControls.toggle()
            }) {
                HStack {
                    Image(systemName: "captions.bubble")
                    Text("Subtitle")
                }
                .padding(15)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
        }
    }
    
    // 返回起始页面
    private var backToHomeView: some View {
        Button(action: {
            viewModel.cleanup()
        }) {
            HStack {
                Text("BACK HOME")
            }
            .padding(15)
            .frame(width: 300)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
    }
    
    // 起始视图
    private var emptyView: some View {
        VStack(spacing: 20) {
            Text("N7-Exam Player")
                .font(.title)
            
            Button("Browse Local Folders") {
                showingFilePicker = true
            }
            .padding(15)
            .frame(width: 250)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            Button("Browse SMB Server") {
                showingSMBBrowser = true
            }
            .padding(15)
            .frame(width: 250)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
    
    // 错误提示视图
    private func errorView(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .padding()
                .background(Color.red.opacity(0.8))
                .cornerRadius(8)
                .padding(.bottom)
        }
    }
}

#Preview {
    ContentView()
}
