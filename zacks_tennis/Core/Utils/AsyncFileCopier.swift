//
//  AsyncFileCopier.swift
//  zacks_tennis
//
//  Created by Claude on 2025-11-04.
//  异步文件复制工具 - 支持进度回调和取消操作
//

import Foundation

/// 异步文件复制错误
enum AsyncFileCopierError: Error {
    case sourceFileNotFound
    case cannotCreateInputStream
    case cannotCreateOutputStream
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

    /// 分块大小（10MB）
    private let chunkSize = 1024 * 1024 * 10

    init() {}

    /// 取消当前复制操作
    func cancel() {
        isCancelled = true
    }

    /// 异步复制文件（带进度回调）
    /// - Parameters:
    ///   - source: 源文件URL
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

        // 验证源文件存在
        guard FileManager.default.fileExists(atPath: source.path) else {
            print("   ❌ 源文件不存在")
            throw AsyncFileCopierError.sourceFileNotFound
        }

        // 获取文件大小
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        print("   文件大小: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")

        // 如果文件小于100MB，使用标准copyItem（更快）
        if fileSize < 100 * 1024 * 1024 {
            print("   ℹ️ 文件小于100MB，使用快速复制模式")
            return try await fastCopy(from: source, to: destination, progress: progress)
        }

        // 大文件使用分块复制
        return try await chunkedCopy(from: source, to: destination, fileSize: fileSize, progress: progress)
    }

    /// 快速复制模式（适用于小文件）
    private func fastCopy(
        from source: URL,
        to destination: URL,
        progress: ProgressHandler?
    ) async throws -> URL {

        // 如果目标文件已存在，先删除
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        // 在后台线程执行复制
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: source, to: destination)
        }.value

        // 更新进度到100%
        await MainActor.run {
            progress?(1.0)
        }

        print("   ✅ 快速复制完成")
        return destination
    }

    /// 分块复制模式（适用于大文件）
    private func chunkedCopy(
        from source: URL,
        to destination: URL,
        fileSize: Int64,
        progress: ProgressHandler?
    ) async throws -> URL {

        print("   ℹ️ 使用分块复制模式")

        // 如果目标文件已存在，先删除
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        // 在后台线程执行分块复制
        let result = try await Task.detached(priority: .userInitiated) { [weak self] () -> URL in
            guard let self = self else {
                throw AsyncFileCopierError.cancelled
            }

            // 创建输入输出流
            guard let inputStream = InputStream(url: source) else {
                throw AsyncFileCopierError.cannotCreateInputStream
            }

            guard let outputStream = OutputStream(url: destination, append: false) else {
                throw AsyncFileCopierError.cannotCreateOutputStream
            }

            inputStream.open()
            outputStream.open()

            defer {
                inputStream.close()
                outputStream.close()
            }

            var buffer = [UInt8](repeating: 0, count: self.chunkSize)
            var totalBytesWritten: Int64 = 0
            var lastProgressUpdate: Double = 0

            while inputStream.hasBytesAvailable {
                // 检查取消标志
                if await self.isCancelled {
                    throw AsyncFileCopierError.cancelled
                }

                // 读取数据块
                let bytesRead = inputStream.read(&buffer, maxLength: self.chunkSize)

                if bytesRead < 0 {
                    // 读取错误
                    if let error = inputStream.streamError {
                        throw AsyncFileCopierError.copyOperationFailed("读取失败: \(error.localizedDescription)")
                    }
                    break
                } else if bytesRead == 0 {
                    // 文件结束
                    break
                }

                // 写入数据块
                let bytesWritten = outputStream.write(buffer, maxLength: bytesRead)

                if bytesWritten < 0 {
                    // 写入错误
                    if let error = outputStream.streamError {
                        throw AsyncFileCopierError.copyOperationFailed("写入失败: \(error.localizedDescription)")
                    }
                    throw AsyncFileCopierError.copyOperationFailed("写入失败")
                }

                totalBytesWritten += Int64(bytesWritten)

                // 更新进度（每1%更新一次）
                let currentProgress = Double(totalBytesWritten) / Double(fileSize)
                if currentProgress - lastProgressUpdate >= 0.01 || currentProgress >= 1.0 {
                    await MainActor.run {
                        progress?(currentProgress)
                    }
                    lastProgressUpdate = currentProgress
                }
            }

            print("   ✅ 分块复制完成，总计: \(ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file))")

            return destination
        }.value

        // 验证复制成功
        guard FileManager.default.fileExists(atPath: destination.path),
              FileManager.default.isReadableFile(atPath: destination.path) else {
            throw AsyncFileCopierError.copyOperationFailed("目标文件不可读")
        }

        return result
    }
}
