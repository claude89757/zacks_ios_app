# Zacks Tennis 🎾

> AI-powered tennis video editing app / AI 智能网球视频剪辑应用

<p align="center">
  <img src="docs/screenshots/screenshot_01.png" width="200" alt="Video List">
  <img src="docs/screenshots/screenshot_03.png" width="200" alt="Rally Details">
  <img src="docs/screenshots/screenshot_04.png" width="200" alt="Export Options">
</p>

## ✨ Features / 功能特性

### 🎬 AI Video Editing / AI 视频剪辑
Automatically analyze tennis videos and detect rallies. Import videos from your photo library, and let AI identify each rally for you.

自动分析网球视频并检测回合。从相册导入视频，让 AI 为你识别每一个回合。

<p align="center">
  <img src="docs/screenshots/screenshot_01.png" width="250" alt="AI Video Editing">
</p>

### 🎵 Audio Detection / 音频智能检测
Detect ball hits by analyzing audio waveforms. Recognizes the distinctive "pop" sound of tennis ball impacts to automatically segment rallies.

通过分析音频波形检测击球。识别网球击打的特征声音，自动分割回合。

**Advantages / 优势:**
- Fast processing / 处理速度快
- Low power consumption / 省电
- Works on-court / 在球场上也能用

<p align="center">
  <img src="docs/screenshots/screenshot_02.png" width="250" alt="Algorithm Description">
</p>

### 📊 Rally Management / 回合管理
Browse all detected rallies in a grid view. Filter by:
- ⭐ Highlights / 精彩回合
- ❤️ Favorites / 收藏
- ⏱️ Long rallies / 长回合

浏览所有检测到的回合，支持筛选精彩片段、收藏和长回合。

<p align="center">
  <img src="docs/screenshots/screenshot_03.png" width="250" alt="Rally Management">
</p>

### 📤 Smart Export / 智能导出
Quick export options:
- Top 10 longest rallies / 最长的 10 个回合
- Top 5 longest rallies / 最长的 5 个回合
- Favorite rallies / 收藏的回合
- Debug mode with ball tracking overlay / 调试模式（带网球轨迹标注）

<p align="center">
  <img src="docs/screenshots/screenshot_04.png" width="250" alt="Export Options">
</p>

## 🎥 Demo / 演示

[Watch Demo Video / 观看演示视频](docs/screenshots/zacks_app.mp4)

## 🛠️ Tech Stack / 技术栈

| Technology | Usage |
|------------|-------|
| **SwiftUI** | Modern declarative UI framework |
| **SwiftData** | Data persistence |
| **AVFoundation** | Video/Audio processing |
| **Vision** | Computer vision (planned) |
| **CoreML** | Machine learning |
| **MVVM** | Architecture pattern |

## 📋 Requirements / 系统要求

- iOS 17.0+
- Xcode 16.0+
- Swift 5.9+

## 🚀 Quick Start / 快速开始

### Clone and Open / 克隆并打开

```bash
git clone https://github.com/your-username/zacks_ios_app.git
cd zacks_ios_app
open zacks_tennis.xcodeproj
```

### Build and Run / 构建运行

1. Open in Xcode / 在 Xcode 中打开
2. Select target device or simulator / 选择目标设备或模拟器
3. Press `⌘+R` to run / 按 `⌘+R` 运行

### Command Line Build / 命令行构建

```bash
# List available simulators / 列出可用模拟器
xcrun simctl list devices available | grep "iPhone"

# Build for simulator / 构建模拟器版本
xcodebuild -project zacks_tennis.xcodeproj \
  -scheme zacks_tennis \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

## 📁 Project Structure / 项目结构

```
zacks_tennis/
├── zacks_tennisApp.swift        # App entry / 应用入口
├── MainTabView.swift            # Tab navigation / 标签导航
├── Core/
│   ├── Models/                  # Data models / 数据模型
│   │   ├── Video.swift          # Video metadata
│   │   └── VideoHighlight.swift # Rally clips
│   └── Services/                # Core services / 核心服务
│       ├── VideoProcessingService.swift
│       ├── ExportManager.swift
│       └── HapticManager.swift
└── Features/
    └── VideoEditor/             # Main feature / 主功能模块
        ├── Views/               # SwiftUI views
        ├── ViewModels/          # MVVM ViewModels
        ├── Models/              # Feature-specific models
        └── Services/            # Feature services
            ├── AudioAnalyzer.swift      # Audio detection
            ├── SimpleHitDetector.swift  # Hit detection
            ├── RallyDetectionEngine.swift
            └── VideoProcessingEngine.swift
```

## 🔬 Algorithm / 算法说明

### Audio-based Rally Detection / 基于音频的回合检测

The app uses audio analysis to detect tennis ball hits:

1. **Audio Extraction** - Extract audio track from video / 从视频提取音轨
2. **Waveform Analysis** - Analyze audio waveform for peaks / 分析波形峰值
3. **Hit Detection** - Identify ball hit sounds using frequency analysis / 通过频率分析识别击球声
4. **Rally Segmentation** - Group consecutive hits into rallies / 将连续击球分组为回合

### Future: Computer Vision / 未来：计算机视觉

Planned features using Vision framework:
- Ball trajectory tracking / 网球轨迹追踪
- Player movement analysis / 球员动作分析
- Shot type classification / 击球类型分类

## 📄 License / 许可证

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

本项目采用 MIT 许可证 - 详情请查看 [LICENSE](LICENSE) 文件。

---

<p align="center">
  Made with ❤️ for tennis lovers / 为网球爱好者用心打造
</p>
