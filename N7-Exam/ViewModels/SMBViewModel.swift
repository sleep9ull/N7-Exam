//
//  SMBViewModel.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import Foundation
import AMSMB2
import SwiftUI

class SMBViewModel: ObservableObject {
    // MARK: - 连接相关状态
    @Published var serverAddress: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var shareName: String = "" // 共享文件夹名称
    
    @Published var isConnecting: Bool = false
    @Published var isConnected: Bool = false
    @Published var errorMessage: String? = nil
    
    // MARK: - 文件浏览相关状态
    @Published var currentPath: String = "/"
    @Published var files: [SMBFileItem] = []
    @Published var isLoading: Bool = false
    
    // MARK: - 下载相关状态
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadFileName: String = ""
    @Published var downloadSize: Int64 = 0
    @Published var downloadedSize: Int64 = 0
    @Published var showDownloadSuccess: Bool = false
    @Published var downloadedFilePath: String = ""
    
    // MARK: - 私有属性
    private var client: SMB2Manager? = nil
    private var downloadTask: Task<Bool, Error>? = nil
    
    // MARK: - 连接方法
    
    /// 连接到SMB服务器
    func connect() async -> Bool {
        await MainActor.run {
            isConnecting = true
            errorMessage = nil
        }
        
        do {
            // 创建 SMB 客户端
            guard let url = URL(string: serverAddress) else {
                throw NSError(domain: "SMBViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的服务器地址"])
            }
            
            // 创建凭证
            let credential = URLCredential(
                user: username,
                password: password,
                persistence: .forSession
            )
            
            // 创建 SMB2Manager 实例
            guard let manager = SMB2Manager(url: url, credential: credential) else {
                throw NSError(domain: "SMBViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建 SMB 客户端"])
            }
            
            client = manager
            
            // 连接到指定共享
            try await client?.connectShare(name: shareName)
            
            // 尝试列出根目录内容以确认连接成功
            _ = try await client?.contentsOfDirectory(atPath: "/")
            
            await MainActor.run {
                isConnecting = false
                isConnected = true
                currentPath = "/"
            }
            
            // 连接成功后，加载文件列表
            await loadFiles(path: "/")
            return true
        } catch {
            await MainActor.run {
                isConnecting = false
                isConnected = false
                errorMessage = "连接失败: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    /// 断开连接
    func disconnect() {
        Task {
            try? await client?.disconnectShare()
            client = nil
            
            await MainActor.run {
                isConnected = false
                files = []
                currentPath = "/"
            }
        }
    }
    
    // MARK: - 文件浏览方法
    
    /// 加载指定路径的文件列表
    func loadFiles(path: String) async {
        guard isConnected, let client = client else { return }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let fileItems = try await client.contentsOfDirectory(atPath: path)
            
            // 将 SMB 文件项目转换为自定义模型
            let mappedFiles = fileItems.compactMap { entry -> SMBFileItem? in
                // 过滤掉特殊目录 "." 和 ".."，以及以"."开头的隐藏文件
                guard let name = entry[.nameKey] as? String,
                      name != "." && name != ".." && !name.hasPrefix(".") else { return nil }
                
                let path = entry[.pathKey] as? String ?? ""
                let type = entry[.fileResourceTypeKey] as? URLFileResourceType ?? .unknown
                let size = entry[.fileSizeKey] as? Int64 ?? 0
                let modificationDate = entry[.contentModificationDateKey] as? Date
                
                return SMBFileItem(
                    name: name,
                    path: path,
                    isDirectory: type == .directory,
                    size: size,
                    modificationDate: modificationDate
                )
            }
            
            await MainActor.run {
                self.files = mappedFiles.sorted(by: { 
                    // 目录优先，然后按名称排序
                    if $0.isDirectory && !$1.isDirectory { return true }
                    if !$0.isDirectory && $1.isDirectory { return false }
                    return $0.name < $1.name
                })
                self.currentPath = path
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载文件失败: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    /// 导航到指定目录
    func navigateToDirectory(_ path: String) async {
        await loadFiles(path: path)
    }
    
    /// 导航到上一级目录
    func navigateUp() async {
        let parentPath = currentPath.split(separator: "/").dropLast().joined(separator: "/")
        let path = parentPath.isEmpty ? "/" : "/\(parentPath)"
        await loadFiles(path: path)
    }
    
    /// 导航到路径中的特定部分
    func navigateToPathPart(_ part: String) async {
        let rootName = "root"
        
        if part == rootName {
            await loadFiles(path: "/")
            return
        }
        
        let parts = currentPath.split(separator: "/")
        let index = parts.firstIndex(where: { String($0) == part })
        
        if let index = index {
            let newPath = "/" + parts[0...index].joined(separator: "/")
            await loadFiles(path: newPath)
        }
    }
    
    // MARK: - 下载相关方法
    
    /// 下载文件
    func downloadFile(_ file: SMBFileItem, downloadManager: DownloadManager) async -> Bool {
        guard isConnected, let client = client else {
            await updateErrorMessage("未连接到SMB服务器")
            return false
        }
        
        // 先取消之前可能存在的下载
        cancelDownload()
        
        // 主线程更新UI状态
        await MainActor.run {
            isLoading = true
            isDownloading = true
            downloadFileName = file.name
            downloadProgress = 0.0
            downloadSize = file.size
            downloadedSize = 0
            showDownloadSuccess = false
            errorMessage = nil
        }
        
        // 创建一个Task<Bool>类型的任务
        let task: Task<Bool, Error> = Task {
            // 创建临时文件URL
            let tempDirectory = FileManager.default.temporaryDirectory
            let tempFileURL = tempDirectory.appendingPathComponent(file.name)
            
            // 清理可能存在的旧临时文件
            if FileManager.default.fileExists(atPath: tempFileURL.path) {
                try FileManager.default.removeItem(at: tempFileURL)
            }
            
            // 检查任务是否被取消
            try Task.checkCancellation()
            
            // 从SMB读取文件
            print("开始从SMB读取文件: \(file.path)")
            let fileData = try await client.contents(atPath: file.path)
            
            // 再次检查取消状态
            try Task.checkCancellation()
            
            print("文件读取完成，大小: \(fileData.count) 字节")
            
            // 写入临时文件
            try fileData.write(to: tempFileURL)
            print("已写入临时文件: \(tempFileURL.path)")
            
            // 再次检查取消状态
            try Task.checkCancellation()
            
            // 更新进度为100%
            await MainActor.run {
                downloadProgress = 1.0
                downloadedSize = Int64(fileData.count)
            }
            
            // 使用DownloadManager保存文件
            let (success, error) = await downloadManager.downloadFile(
                from: tempFileURL,
                filename: file.name
            )
            
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempFileURL)
            
            // 更新下载结果
            await MainActor.run {
                isDownloading = false
                isLoading = false // 确保加载指示器停止
                
                if let error = error {
                    errorMessage = "下载失败: \(error.localizedDescription)"
                    print("下载失败: \(error)")
                } else if success {
                    showDownloadSuccess = true
                    print("下载成功")
                }
            }
            
            // 返回下载是否成功
            return success
        }
        
        // 保存任务引用以便可以取消
        downloadTask = task
        
        do {
            // 等待任务完成并返回结果
            return try await task.value
        } catch is CancellationError {
            // 处理取消的情况
            print("下载已取消")
            
            // 确保UI更新
            await MainActor.run {
                isDownloading = false
                isLoading = false
                downloadProgress = 0
            }
            
            return false
        } catch {
            // 处理其他错误
            print("下载过程中出错: \(error.localizedDescription)")
            
            await MainActor.run {
                isDownloading = false
                isLoading = false
                errorMessage = "下载失败: \(error.localizedDescription)"
            }
            
            return false
        }
    }
    
    /// 取消下载
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        
        Task { @MainActor in
            isDownloading = false
            isLoading = false // 确保加载指示器停止
            downloadProgress = 0.0
            downloadFileName = ""
        }
    }
    
    // MARK: - URL和播放相关方法
    
    /// 生成SMB流URL，用于VLCKit播放
    func getSMBStreamURL(for filePath: String) -> URL? {
        // 确保有服务器地址和凭证
        guard !serverAddress.isEmpty else {
            print("SMB URL 错误：服务器地址为空")
            return nil
        }
        
        // 清理服务器地址
        let cleanServerAddress = serverAddress.replacingOccurrences(of: "smb://", with: "")
                                             .replacingOccurrences(of: "//", with: "")
                                             .replacingOccurrences(of: "http://", with: "")
                                             .replacingOccurrences(of: "https://", with: "")
                                             .trimmingCharacters(in: .whitespacesAndNewlines)
                                             .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // 清理共享名
        let cleanShareName = shareName.trimmingCharacters(in: .whitespacesAndNewlines)
                                      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // 处理文件路径 - 去除前导斜杠
        var cleanFilePath = filePath
        if cleanFilePath.hasPrefix("/") {
            cleanFilePath.removeFirst()
        }
        cleanFilePath = cleanFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let smbPath = "/\(cleanShareName)/\(cleanFilePath)"
        
        var urlString = "smb://"
        
        // 添加用户名和密码（如果提供）
        if !username.isEmpty {
            let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            urlString += encodedUsername
            
            if !password.isEmpty {
                let specialCharacters = [";", "'", "\"", "`", "\\", "&"]
                var encodedPassword = password
                
                for char in specialCharacters {
                    encodedPassword = encodedPassword.replacingOccurrences(of: char, with: char.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? char)
                }
                
                urlString += ":\(encodedPassword)"
            }
            
            urlString += "@"
        }
        
        // 添加服务器地址和路径
        urlString += "\(cleanServerAddress)\(smbPath)"
        
        print("SMB URL: \(urlString)")
        guard let url = URL(string: urlString) else {
            print("无法创建URL：\(urlString)")
            return nil
        }
        return url
    }
    
    /// 处理文件点击，确定是浏览目录还是准备播放媒体文件
    func handleFileTap(_ file: SMBFileItem, playerViewModel: VideoPlayerViewModel) async -> Bool {
        // 如果是目录，导航到该目录
        if file.isDirectory {
            await navigateToDirectory(file.path)
            return true
        } 
        
        // 如果是文件，尝试播放
        return await playFile(file, playerViewModel: playerViewModel)
    }
    
    /// 播放文件
    func playFile(_ file: SMBFileItem, playerViewModel: VideoPlayerViewModel) async -> Bool {
        await MainActor.run {
            isLoading = true
        }
        
        // 获取SMB URL
        guard let streamURL = getSMBStreamURL(for: file.path) else {
            await updateErrorMessage("无法创建播放URL")
            return false
        }
        
        // 准备播放
        await playerViewModel.loadVideo(from: streamURL)
        
        await MainActor.run {
            isLoading = false
        }
        
        return true
    }
    
    // MARK: - 辅助方法
    
    /// 返回当前SMB客户端，如果已连接
    func getSMBClient() -> SMB2Manager? {
        guard isConnected else { return nil }
        return client
    }
    
    /// 更新错误消息
    @MainActor
    private func updateErrorMessage(_ message: String) {
        errorMessage = message
        isLoading = false
    }
}

// MARK: - 模型定义

/// 用于表示 SMB 文件项的模型
struct SMBFileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
    
    // 格式化文件大小
    var formattedSize: String {
        if isDirectory {
            return "文件夹"
        }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

/// 错误消息模型，用于Alert
struct ErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}