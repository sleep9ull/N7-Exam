//
//  SubtitleControlView.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import SwiftUI
import UniformTypeIdentifiers

struct SubtitleControlView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @State private var showingSubtitlePicker = false
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Subtitle Control")
                .font(.headline)
                .padding(.top)
            
            // 字幕文件添加/取消按钮
            Button(action: {
                if viewModel.subtitleEnabled {
                    viewModel.disableSubtitle()
                } else {
                    showingSubtitlePicker = true
                }
            }) {
                HStack {
                    Image(systemName: viewModel.subtitleEnabled ? "xmark.circle" : "plus")
                    Text(viewModel.subtitleEnabled ? "Remove Subtitle" : "Load Subtitle")
                }
                .padding(10)
                .font(.subheadline)
                .background(viewModel.subtitleEnabled ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .sheet(isPresented: $showingSubtitlePicker) {
                DocumentPicker(
                    contentTypes: [
                        .plainText,
                        UTType(filenameExtension: "srt")!,
                        UTType(filenameExtension: "ass")!,
                    ],
                    onSelect: { url in
                        viewModel.loadSubtitle(from: url)
                        showingSubtitlePicker = false
                    }
                )
            }
            
            // 字幕时间调整控制
            VStack(spacing: 10) {
                Text("Subtitle Time Offset: \(String(format: "%.1f", viewModel.subtitleDelay))s")
                    .font(.subheadline)
                
                HStack(spacing: 10) {
                    // 字幕快退按钮 (提前显示)
                    AdjustButton(text: "-3s", action: { viewModel.subtitleForward(seconds: 3.0) })
                    AdjustButton(text: "-1s", action: { viewModel.subtitleForward(seconds: 1.0) })
                    
                    // 重置按钮
                    Button(action: {
                        viewModel.resetSubtitleDelay()
                    }) {
                        Text("RESET")
                            .padding(10)
                            .font(.caption)
                            .fontWeight(.bold)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    
                    // 字幕快进按钮 (延后显示)
                    AdjustButton(text: "+1s", action: { viewModel.subtitleBackward(seconds: 1.0) })
                    AdjustButton(text: "+3s", action: { viewModel.subtitleBackward(seconds: 3.0) })
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private func AdjustButton(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .padding(10)
                .font(.caption)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
        }
    }
}

#Preview {
    SubtitleControlView(viewModel: VideoPlayerViewModel())
}
