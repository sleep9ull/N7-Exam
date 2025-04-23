//
//  Utils.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import Foundation

class DownloadManager: NSObject, ObservableObject {
    private var downloadTask: URLSessionDownloadTask?
    private var completionContinuation: CheckedContinuation<(Bool, Error?), Never>?
    private var progressContinuation: AsyncStream<Double>.Continuation?
    
    @Published private(set) var progress: Double = 0
    @Published private(set) var isDownloading = false
    
    // 下载文件到 Documents 目录
    @MainActor
    func downloadFile(from url: URL, filename: String) async -> (Bool, Error?) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var destinationURL = documentsDirectory.appendingPathComponent(filename)
        
        // 处理文件重名
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let fileExtension = destinationURL.pathExtension
            let filenameWithoutExt = destinationURL.deletingPathExtension().lastPathComponent
            let newFilename = "\(filenameWithoutExt)_\(timestamp).\(fileExtension)"
            destinationURL = documentsDirectory.appendingPathComponent(newFilename)
            print("文件已存在，将下载到新文件名: \(newFilename)")
        }
        
        // 开始下载
        self.isDownloading = true
        self.progress = 0
        
        return await withCheckedContinuation { continuation in
            self.completionContinuation = continuation
            
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            downloadTask = session.downloadTask(with: url)
            downloadTask?.taskDescription = destinationURL.path // 存储目标路径
            downloadTask?.resume()
        }
    }
    
    // 获取下载进度
    func downloadProgress() -> AsyncStream<Double> {
        return AsyncStream { continuation in
            self.progressContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.progressContinuation = nil
                }
            }
        }
    }
    
    // 取消下载
    @MainActor
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        let cancelError = NSError(domain: "DownloadCancelled", code: -999, userInfo: [NSLocalizedDescriptionKey: "下载已取消"])
        completionContinuation?.resume(returning: (false, cancelError))
        completionContinuation = nil
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destinationPath = downloadTask.taskDescription,
              let destinationURL = URL(string: "file://" + destinationPath) else {
            print("无法获取目标路径")
            Task { @MainActor in
                self.downloadTask = nil
                self.isDownloading = false
                self.completionContinuation?.resume(returning: (false, nil))
                self.completionContinuation = nil
            }
            return
        }
        
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("文件成功下载到: \(destinationURL.path)")
            Task { @MainActor in
                self.downloadTask = nil
                self.isDownloading = false
                self.completionContinuation?.resume(returning: (true, nil))
                self.completionContinuation = nil
            }
        } catch {
            print("移动文件失败: \(error)")
            Task { @MainActor in
                self.downloadTask = nil
                self.isDownloading = false
                self.completionContinuation?.resume(returning: (false, error))
                self.completionContinuation = nil
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progressValue = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.progress = progressValue
            self.progressContinuation?.yield(progressValue)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("下载失败: \(error)")
            Task { @MainActor in
                self.isDownloading = false
                self.completionContinuation?.resume(returning: (false, error))
                self.completionContinuation = nil
                self.downloadTask = nil
            }
        }
    }
}