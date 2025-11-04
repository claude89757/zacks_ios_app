//
//  AsyncFileCopier.swift
//  zacks_tennis
//
//  Created by Claude on 2025-11-04.
//  异步文件复制工具 - 支持进度回调和取消操作
//  修复：支持安全作用域资源访问（PhotosPicker临时文件）
//

import Foundation

/// 异步文件复制错误
enum AsyncFileCopierError: Error {
    case sourceFileNotFound
    case securityScopedResourceAccessFailed
    case copyOperationFailed(String)
    case cancelled
}

/// 异步文件复制工具类
@MainActor
class AsyncFileCopier {

    /// 文件复制进度回调
    typealias ProgressHandler = (Double) -> Void

    /// 取消标志
    private var isCancelled = false

    /// 进度定时器
    private var progressTimer: Timer?

    init() {}

    /// 取消当前复制操作
    func cancel() {
        isCancelled = true
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// 异步复制文件（带进度回调）
    /// - Parameters:
    ///   - source: 源文件URL（支持安全作用域资源）
    ///   - destination: 目标文件URL
    ///   - progress: 进度回调（0.0-1.0）
    /// - Returns: 目标文件URL
    func copyFile(
        from source: URL,
        to destination: URL,
        progress: ProgressHandler? = nil
    ) async throws -> URL {

        print("📋 [AsyncFileCopier] 开始复制文件")
        print("   源: \(source.path)")
        print("   目标: \(destination.path)")

        // 重置取消标志
        isCancelled = false

        // 🔑 关键修复：访问安全作用域资源（PhotosPicker提供的临时文件需要）
        let accessGranted = source.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                source.stopAccessingSecurityScopedResource()
                print("   🔓 已释放安全作用域资源访问")
            }
        }

        print("   🔑 安全作用域访问: \(accessGranted ? "已授权" : "不需要")")

        // 验证源文件存在
        guard FileManager.default.fileExists(atPath: source.path) else {
            print("   ❌ 源文件不存在")
            throw AsyncFileCopierError.sourceFileNotFound
        }

        // 获取文件大小
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        print("   文件大小: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")

        // 如果目标文件已存在，先删除
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        // 估算复制时间（基于文件大小，约 100MB/秒）
        let estimatedSeconds = max(Double(fileSize) / (100.0 * 1024 * 1024), 1.0)
        print("   ⏱️  预估复制时间: \(String(format: "%.1f", estimatedSeconds))秒")

        // 🚀 优化：使用后台线程 + 进度估算
        return try await copyWithProgressEstimation(
            from: source,
            to: destination,
            fileSize: fileSize,
            estimatedDuration: estimatedSeconds,
            progress: progress
        )
    }

    /// 使用进度估算的复制方法
    private func copyWithProgressEstimation(
        from source: URL,
        to destination: URL,
        fileSize: Int64,
        estimatedDuration: TimeInterval,
        progress: ProgressHandler?
    ) async throws -> URL {

        let startTime = Date()
        var currentProgress: Double = 0.0

        // 启动进度估算定时器（每0.1秒更新一次）
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, !self.isCancelled else { return }

            let elapsed = Date().timeIntervalSince(startTime)
            currentProgress = min(elapsed / estimatedDuration, 0.95) // 最多到95%，等实际完成后跳到100%

            Task { @MainActor in
                progress?(currentProgress)
            }
        }
        self.progressTimer = timer

        defer {
            timer.invalidate()
            self.progressTimer = nil
        }

        // 在后台线程执行实际复制
        let result = try await Task.detached(priority: .userInitiated) { () -> URL in
            do {
                // 使用 FileManager 复制（简单可靠）
                try FileManager.default.copyItem(at: source, to: destination)
                print("   ✅ 文件复制成功")
                return destination
            } catch {
                print("   ❌ 文件复制失败: \(error.localizedDescription)")
                throw AsyncFileCopierError.copyOperationFailed(error.localizedDescription)
            }
        }.value

        // 复制完成，立即更新进度到100%
        await MainActor.run {
            progress?(1.0)
        }

        // 验证复制成功
        guard FileManager.default.fileExists(atPath: destination.path),
              FileManager.default.isReadableFile(atPath: destination.path) else {
            throw AsyncFileCopierError.copyOperationFailed("目标文件不可读")
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        print("   ⏱️  实际复制时间: \(String(format: "%.2f", actualDuration))秒")
        print("   📊 平均速度: \(ByteCountFormatter.string(fromByteCount: Int64(Double(fileSize) / actualDuration), countStyle: .file))/s")

        return result
    }
}
