//
//  SMBBrowserView.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import SwiftUI

struct SMBBrowserView: View {
    // 数据源ViewModel
    @ObservedObject var viewModel: SMBViewModel
    @Environment(\.dismiss) private var dismiss
    
    // 依赖注入
    let playerViewModel: VideoPlayerViewModel
    let downloadManager: DownloadManager
    
    // 初始化方法
    init(viewModel: SMBViewModel, playerViewModel: VideoPlayerViewModel, downloadManager: DownloadManager) {
        self.viewModel = viewModel
        self.playerViewModel = playerViewModel
        self.downloadManager = downloadManager
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 主内容决定显示登录页面还是文件浏览页面
                if viewModel.isConnected {
                    connectedView
                } else {
                    SMBLoginView(viewModel: viewModel)
                }
                
                // 加载指示器
                if viewModel.isLoading {
                    loadingView
                }
                
                // 下载进度指示器
                if viewModel.isDownloading {
                    downloadProgressView
                }
            }
            .navigationTitle("SMB Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    connectionButton
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Close")
                    }
                }
            }
            // 下载成功提示
            .alert("Download Complete", isPresented: $viewModel.showDownloadSuccess) {
                Button("OK") { viewModel.showDownloadSuccess = false }
            } message: {
                Text("File downloaded to Files app,\nPath: Device > My Apps")
            }
            // 错误提示
            .alert(item: viewErrorMessage) { error in
                Alert(
                    title: Text("Error"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // MARK: - 视图组件
    
    // 连接后的主内容视图
    private var connectedView: some View {
        VStack {
            pathNavigationBar
            fileListView()
        }
    }
    
    // 文件列表视图
    private func fileListView() -> some View {
        List {
            if viewModel.files.isEmpty {
                emptyDirectoryView
            } else {
                ForEach(viewModel.files) { file in
                    fileRow(file)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            // 下拉刷新
            Task {
                await viewModel.loadFiles(path: viewModel.currentPath)
            }
        }
    }
    
    // 路径导航栏
    private var pathNavigationBar: some View {
        HStack {
            ScrollView(.horizontal, showsIndicators: false) {
                pathBreadcrumbView
            }
            
            Spacer()
            
            navigationUpButton
        }
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
    }
    
    // 路径面包屑视图
    private var pathBreadcrumbView: some View {
        HStack(spacing: 0) {
            let rootName = "root"
            
            ForEach([rootName] + viewModel.currentPath.split(separator: "/").map { String($0) }, id: \.self) { part in
                pathPartView(part: part, rootName: rootName)
            }
        }
        .padding(.horizontal)
    }
    
    // 路径部分视图
    private func pathPartView(part: String, rootName: String) -> some View {
        HStack(spacing: 2) {
            if part != rootName {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Button(action: {
                Task {
                    await viewModel.navigateToPathPart(part)
                }
            }) {
                Text(part)
                    .font(.system(size: part == rootName ? 15 : 14))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 7)
                    .foregroundColor(part == rootName ? .blue : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.blue.opacity(0.1))
                            .opacity(part == rootName ? 1 : 0)
                    )
            }
        }
    }
    
    // 向上导航按钮
    private var navigationUpButton: some View {
        Button(action: {
            if viewModel.currentPath != "/" {
                Task {
                    await viewModel.navigateUp()
                }
            }
        }) {
            Image(systemName: "arrowshape.up.circle")
                .font(.system(size: 20))
                .foregroundColor(viewModel.currentPath == "/" ? .gray : .blue)
        }
        .disabled(viewModel.currentPath == "/")
        .padding(.horizontal, 8)
    }
    
    // 加载视图
    private var loadingView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            ProgressView()
                .scaleEffect(1.5)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 100, height: 100)
                )
        }
    }
    
    // 空目录视图
    private var emptyDirectoryView: some View {
        ContentUnavailableView(
            "No Files",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Current directory is empty")
        )
    }
    
    // 连接按钮
    private var connectionButton: some View {
        Group {
            if viewModel.isConnected {
                Button(action: {
                    viewModel.disconnect()
                }) {
                    Text("Disconnect")
                }
            } else {
                Button(action: {
                    // 无需操作，已经显示登录页面
                }) {
                    Text("Connect")
                }
            }
        }
    }
    
    // 文件行
    private func fileRow(_ file: SMBFileItem) -> some View {
        Button(action: {
            Task {
                if await viewModel.handleFileTap(file, playerViewModel: playerViewModel) {
                    // 如果成功播放文件，关闭当前视图
                    if !file.isDirectory {
                        dismiss() // 仅当点击的是文件而不是目录时关闭
                    }
                }
            }
        }) {
            HStack {
                Image(systemName: file.isDirectory ? "folder" : "doc")
                    .foregroundColor(file.isDirectory ? .blue : .gray)
                    .font(.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 16))
                        .lineLimit(1)
                    
                    HStack {
                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        if let date = file.modificationDate {
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(dateFormatter.string(from: date))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 3)
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if !file.isDirectory {
                Button(action: {
                    Task {
                        if await viewModel.playFile(file, playerViewModel: playerViewModel) {
                            dismiss() // 成功播放后关闭
                        }
                    }
                }) {
                    Label("Play", systemImage: "play.circle")
                }
                
                Button(action: {
                    Task {
                        _ = await viewModel.downloadFile(file, downloadManager: downloadManager)
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
    }
    
    // 下载进度视图
    private var downloadProgressView: some View {
        VStack {
            Text("Downloading...")
                .font(.subheadline)
            
            Text("\(viewModel.downloadFileName)")
                .font(.caption)
                .lineLimit(1)
                .padding(.top, 2)
            
            HStack(spacing: 10) {
                ProgressView(value: viewModel.downloadProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                
                Text("\(Int(viewModel.downloadProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }
            .padding(.top, 5)
            
            Button(action: {
                viewModel.cancelDownload()
            }) {
                Text("Cancel")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(20)
        .frame(width: 300)
        .shadow(radius: 15)
    }
    
    // MARK: - 辅助属性
    
    // 错误信息绑定
    private var viewErrorMessage: Binding<ErrorMessage?> {
        Binding<ErrorMessage?>(
            get: {
                if let error = viewModel.errorMessage {
                    return ErrorMessage(message: error)
                }
                return nil
            },
            set: { newValue in
                viewModel.errorMessage = newValue?.message
            }
        )
    }
    
    // 日期格式化
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - 预览
#Preview {
    SMBBrowserView(
        viewModel: SMBViewModel(),
        playerViewModel: VideoPlayerViewModel(),
        downloadManager: DownloadManager()
    )
}

// 专门用于预览下载进度组件
#if DEBUG
extension SMBBrowserView {
    static var previewDownloadProgress: some View {
        let viewModel = SMBViewModel()
        // 设置必要的状态变量
        viewModel.isDownloading = true
        viewModel.downloadProgress = 0.65
        viewModel.downloadFileName = "sample_movie.mkv"
        
        return SMBBrowserView(
            viewModel: viewModel,
            playerViewModel: VideoPlayerViewModel(),
            downloadManager: DownloadManager()
        ).downloadProgressView
            .previewLayout(.sizeThatFits)
            .padding()
            .previewDisplayName("Download Progress View")
    }
}

#Preview("Download Progress") {
    SMBBrowserView.previewDownloadProgress
}
#endif
