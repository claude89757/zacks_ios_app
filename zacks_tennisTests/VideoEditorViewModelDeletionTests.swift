import Foundation
import SwiftData
import Testing
@testable import Zacks网球视频剪辑

struct VideoEditorViewModelDeletionTests {
    @MainActor
    @Test("删除视频会清理数据库记录和相关本地文件")
    func deleteVideoRemovesPersistedFilesAndRecord() throws {
        let context = try makeModelContext()
        let viewModel = VideoEditorViewModel()
        viewModel.configure(modelContext: context)

        let fixture = try makeVideoFixture()
        defer { fixture.cleanupRemainingFiles() }

        let video = fixture.video
        context.insert(video)
        try context.save()

        try viewModel.deleteVideo(video)

        #expect(FileManager.default.fileExists(atPath: fixture.originalURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.thumbnailURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.exportedURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.diagnosticURL.path) == false)

        let videos = try context.fetch(FetchDescriptor<Video>())
        #expect(videos.isEmpty)
    }

    @MainActor
    @Test("旧数据没有音频诊断文件路径时也能安全删除")
    func deleteVideoWithoutDiagnosticPathStillSucceeds() throws {
        let context = try makeModelContext()
        let viewModel = VideoEditorViewModel()
        viewModel.configure(modelContext: context)

        let fixture = try makeVideoFixture(includeDiagnosticFile: false)
        defer { fixture.cleanupRemainingFiles() }

        let video = fixture.video
        context.insert(video)
        try context.save()

        try viewModel.deleteVideo(video)

        let videos = try context.fetch(FetchDescriptor<Video>())
        #expect(videos.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.originalURL.path) == false)
    }

    @MainActor
    @Test("未配置 model context 时删除会抛出错误")
    func deleteVideoWithoutConfiguredContextThrows() {
        let viewModel = VideoEditorViewModel()
        let video = Video(
            title: "Delete Test",
            originalFilePath: "missing.mov",
            duration: 10,
            width: 1920,
            height: 1080,
            fileSize: 1024
        )

        #expect(throws: (any Error).self) {
            try viewModel.deleteVideo(video)
        }
    }
}

private extension VideoEditorViewModelDeletionTests {
    @MainActor
    func makeModelContext() throws -> ModelContext {
        let schema = Schema([Video.self, VideoHighlight.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    func makeVideoFixture(includeDiagnosticFile: Bool = true) throws -> VideoFixture {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let token = UUID().uuidString

        let originalURL = documentsDirectory.appendingPathComponent("test-video-\(token).mov")
        let thumbnailURL = documentsDirectory.appendingPathComponent("test-thumb-\(token).jpg")
        let exportedURL = documentsDirectory.appendingPathComponent("test-export-\(token).mp4")
        let diagnosticURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio-diagnostic-\(token).json")

        try Data("video".utf8).write(to: originalURL)
        try Data("thumb".utf8).write(to: thumbnailURL)
        try Data("export".utf8).write(to: exportedURL)

        if includeDiagnosticFile {
            try Data("diagnostic".utf8).write(to: diagnosticURL)
        }

        let video = Video(
            title: "Delete Test",
            originalFilePath: originalURL.lastPathComponent,
            duration: 10,
            width: 1920,
            height: 1080,
            fileSize: 1024
        )
        video.thumbnailPath = thumbnailURL.lastPathComponent
        video.addExportedFile(
            ExportedFile(
                id: UUID(),
                filePath: exportedURL.lastPathComponent,
                exportedAt: Date(),
                type: "top1",
                fileSize: 256
            )
        )
        video.audioDiagnosticDataPath = includeDiagnosticFile ? diagnosticURL.path : nil

        return VideoFixture(
            video: video,
            originalURL: originalURL,
            thumbnailURL: thumbnailURL,
            exportedURL: exportedURL,
            diagnosticURL: diagnosticURL
        )
    }
}

private struct VideoFixture {
    let video: Video
    let originalURL: URL
    let thumbnailURL: URL
    let exportedURL: URL
    let diagnosticURL: URL

    func cleanupRemainingFiles() {
        let fileManager = FileManager.default
        for url in [originalURL, thumbnailURL, exportedURL, diagnosticURL] where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
