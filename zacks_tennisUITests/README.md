# 网球视频回合剪辑算法

## 📋 项目概述

这是一个高精度的网球视频回合检测算法,使用多特征融合技术实现:
- **目标准确率**: ≥ 85% (回合边界误差 < 1秒)
- **处理速度**: 30分钟视频 < 10分钟
- **评分算法**: 智能精彩度评分 (0-100)

## 🏗️ 架构设计

### 核心组件

```
RallyDetectionEngine (主引擎)
├── AudioAnalyzer (音频分析)
│   ├── 峰值检测 (击球声)
│   └── FFT频谱分析 (500-4000Hz)
├── MovementAnalyzer (视频分析)
│   ├── Vision人体姿态检测
│   └── 运动强度计算
├── TemporalAnalyzer (时序分析)
│   ├── 状态机 (IDLE → RALLY_START → IN_RALLY → RALLY_END)
│   └── 回合边界检测
├── FeatureFusion (特征融合)
│   ├── 音视频同步
│   └── 置信度计算
└── ExcitementScorer (评分算法)
    ├── 时长评分 (30%)
    ├── 强度评分 (40%)
    ├── 击球频率 (20%)
    └── 连续性 (10%)
```

### 文件结构

```
zacks_tennisUITests/
├── RallyDetection/              # 算法核心
│   ├── Models/
│   │   ├── DetectionModels.swift      # 数据模型
│   │   └── ThresholdConfig.swift      # 可调参数
│   ├── RallyDetectionEngine.swift     # 主引擎
│   ├── AudioAnalyzer.swift            # 音频分析
│   ├── MovementAnalyzer.swift         # 视频分析
│   ├── TemporalAnalyzer.swift         # 时序分析
│   ├── FeatureFusion.swift            # 特征融合
│   └── ExcitementScorer.swift         # 评分算法
├── TestHelpers/                 # 测试工具
│   ├── VideoTestLoader.swift          # 加载测试视频
│   ├── GroundTruthParser.swift        # 解析标注数据
│   └── AccuracyEvaluator.swift        # 准确率评估
└── RallyDetectionTests.swift    # 测试用例
```

## 🚀 快速开始

### 1. 准备测试视频

将测试视频放入项目根目录的 `test_videos/` 文件夹:

```
test_videos/
├── match1.mp4           # 测试视频
├── match1.json          # 标注数据 (可选)
├── match2.mp4
└── match2.json
```

### 2. 标注数据格式 (可选,用于准确率验证)

创建与视频同名的 `.json` 文件:

```json
{
  "video": "match1.mp4",
  "rallies": [
    {
      "startTime": 12.5,
      "endTime": 28.3,
      "excitementScore": 85,
      "notes": "Long baseline rally"
    },
    {
      "startTime": 45.0,
      "endTime": 58.2,
      "excitementScore": 92,
      "notes": "Fast-paced volley exchange"
    }
  ],
  "metadata": {
    "annotator": "Your Name",
    "date": "2025-11-02"
  }
}
```

### 3. 运行测试

在 Xcode 中:
1. 选择 `zacks_tennisUITests` scheme
2. ⌘ + U 运行所有测试
3. 或单独运行特定测试:
   - `testRallyDetectionAccuracy` - 准确率验证
   - `testProcessingSpeed` - 性能测试
   - `testExcitementScoringIsReasonable` - 评分验证

## 🧪 测试套件

### 主要测试用例

| 测试 | 描述 | 验收标准 |
|------|------|----------|
| `testEngineCanProcessVideo` | 基本处理功能 | 成功检测回合 |
| `testRallyDetectionAccuracy` | 准确率验证 | ≥ 85% 准确率,边界误差 < 1s |
| `testProcessingSpeed` | 性能测试 | 30min视频 < 10min处理 |
| `testExcitementScoringIsReasonable` | 评分合理性 | 分数 0-100,有分布差异 |
| `testAudioAnalyzer` | 音频分析单元测试 | 检测到击球声 |
| `testMovementAnalyzer` | 视频分析单元测试 | 检测到人体运动 |
| `testConfigurationPresets` | 配置预设测试 | 不同配置正常工作 |

### 运行特定测试

```bash
# 运行所有测试
xcodebuild test -scheme zacks_tennis -destination 'platform=iOS Simulator,name=iPhone 15'

# 运行单个测试
xcodebuild test -scheme zacks_tennis -only-testing:zacks_tennisUITests/RallyDetectionTests/testRallyDetectionAccuracy
```

## 🎛️ 配置调优

### 预设配置

```swift
// 默认配置
let config = ThresholdConfig()

// 高精度模式 (更慢,更准确)
let config = ThresholdConfig.highPrecision

// 快速模式 (更快,准确率略低)
let config = ThresholdConfig.fast

// 室内场地
let config = ThresholdConfig.indoor

// 室外场地
let config = ThresholdConfig.outdoor
```

### 自定义配置

```swift
var config = ThresholdConfig()

// 音频参数
config.audioAmplitudeThreshold = 0.35    // 击球声幅度阈值
config.hitSoundFrequencyRange = 500...4000  // 击球声频率范围

// 视频参数
config.movementIntensityThreshold = 0.4  // 运动强度阈值
config.videoAnalysisFPS = 5.0            // 分析帧率

// 时序参数
config.minRallyDuration = 3.0            // 最小回合时长
config.maxPauseDuration = 2.0            // 最大暂停时长

// 特征融合权重
config.videoWeight = 0.5                 // 视频权重
config.audioWeight = 0.3                 // 音频权重
config.temporalWeight = 0.2              // 时序权重

// 评分权重
config.durationWeight = 0.3              // 时长权重
config.intensityWeight = 0.4             // 强度权重
config.hitFrequencyWeight = 0.2          // 击球频率权重
config.continuityWeight = 0.1            // 连续性权重
```

### 保存/加载配置

```swift
// 保存配置
try config.save(to: configURL)

// 加载配置
let config = try ThresholdConfig.load(from: configURL)
```

## 📊 使用示例

### 基本用法

```swift
import XCTest

let engine = RallyDetectionEngine()
let videoURL = URL(fileURLWithPath: "test_videos/match1.mp4")

// 检测回合
let result = try await engine.detectRallies(in: videoURL)

print("检测到 \(result.totalRallies) 个回合")
print("处理时间: \(result.processingTime)秒")

// 获取最精彩的回合
if let topRally = result.topExcitingRally {
    print("最精彩回合: \(topRally.startTime)s - \(topRally.endTime)s")
    print("评分: \(topRally.excitementScore)")
}

// 生成诊断报告
let report = engine.generateDiagnosticReport(result: result)
print(report)
```

### 验证准确率

```swift
// 加载测试视频和标注
let testVideo = try VideoTestLoader.loadTestVideo(named: "match1")
let groundTruth = try GroundTruthParser.parse(testVideo: testVideo!)

// 运行检测
let result = try await engine.detectRallies(in: testVideo.url)

// 评估准确率
let metrics = AccuracyEvaluator.evaluate(
    detected: result.rallies,
    groundTruth: groundTruth.rallies,
    tolerance: 1.0
)

print(metrics.report())
print("准确率: \(metrics.accuracy * 100)%")
print("平均边界误差: \(metrics.averageBoundaryError)秒")
```

### 批量处理

```swift
let testVideos = try VideoTestLoader.loadTestVideos()

for video in testVideos {
    let result = try await engine.detectRallies(in: video.url)
    print("\(video.name): \(result.totalRallies) rallies")
}
```

## 🔧 调试工具

### 生成详细评分分析

```swift
let breakdown = engine.generateScoringBreakdown(for: rally)
print(breakdown)
```

输出示例:
```
Excitement Score Breakdown
═════════════════════════════
Rally: 12.5s - 28.3s (Duration: 15.8s)

Components:
- Duration:       52.7 (weight: 30%)
- Intensity:      78.5 (weight: 40%)
- Hit Frequency:  65.0 (weight: 20%)
- Continuity:     88.0 (weight: 10%)

Base Score:       72.3
Bonus Points:   +  5.0
Penalties:      -  0.0
─────────────────────────────
Final Score:      77.3
```

### 匹配分析

```swift
let analysis = AccuracyEvaluator.generateMatchAnalysis(
    detected: result.rallies,
    groundTruth: groundTruth.rallies,
    tolerance: 1.0
)
print(analysis)
```

## 📈 性能优化

### 并行处理

```swift
var config = ThresholdConfig()
config.enableParallelProcessing = true  // 音视频并行分析
let engine = RallyDetectionEngine(config: config)
```

### 分块处理 (长视频)

```swift
// 自动分块处理超过10分钟的视频
let result = try await engine.detectRalliesWithChunking(in: videoURL)
```

### 调整分析帧率

```swift
var config = ThresholdConfig()
config.videoAnalysisFPS = 3.0  // 降低到 3fps (更快,略低准确率)
```

## 🎯 验收标准

### 准确率要求

✅ **回合检测准确率 > 85%**
- 定义: 检测到的回合与标注回合的匹配率
- 计算: (正确检测数 / 总标注回合数) × 100%

✅ **回合边界误差 < 1秒**
- 定义: 检测到的回合起止时间与标注的误差
- 计算: |detected_time - ground_truth_time| < 1.0s

✅ **精彩度评分合理**
- 分数范围: 0-100
- 有明显区分度
- 符合人工判断

### 性能要求

✅ **处理速度: 30分钟视频 < 10分钟**
- 目标处理速率: ≥ 3× 实时
- 测试基准: iPhone 13 或同等性能

## 🐛 常见问题

### 1. 没有检测到回合

**可能原因**:
- 视频质量差
- 无音频轨道
- 阈值设置过高

**解决方案**:
```swift
var config = ThresholdConfig()
config.movementIntensityThreshold = 0.3  // 降低阈值
config.audioAmplitudeThreshold = 0.25
```

### 2. 误检太多

**可能原因**:
- 背景噪音
- 观众欢呼声
- 阈值设置过低

**解决方案**:
```swift
var config = ThresholdConfig()
config.movementIntensityThreshold = 0.5  // 提高阈值
config.minRallyDuration = 5.0            // 增加最小时长
```

### 3. 边界不准确

**可能原因**:
- 音视频不同步
- 击球声识别不准

**解决方案**:
```swift
var config = ThresholdConfig()
config.audioVideoSyncOffset = 0.1        // 调整同步偏移
config.rallyStartPadding = 1.5           // 增加起始padding
config.rallyEndPadding = 1.5             // 增加结束padding
```

## 📝 开发说明

### 添加新特征

1. 在 `DetectionModels.swift` 添加数据模型
2. 在相应分析器中实现特征提取
3. 在 `FeatureFusion.swift` 中集成新特征
4. 更新 `ThresholdConfig.swift` 添加配置参数
5. 编写单元测试验证

### 调优流程

1. 使用少量测试视频建立基准
2. 调整单个参数,观察影响
3. 使用 `generateScoringBreakdown()` 分析
4. 迭代优化直到达标
5. 在完整测试集上验证

## 📚 技术细节

### 算法流程

```
1. 音视频分析 (并行)
   ├── 音频: 提取 → 峰值检测 → FFT分析 → 击球声识别
   └── 视频: 提取帧 → 姿态检测 → 运动强度计算

2. 时序分析
   └── 状态机 → 候选回合 → 边界优化

3. 特征融合
   └── 音视频对齐 → 置信度计算 → 假阳性过滤

4. 评分排序
   └── 多维度评分 → 归一化 → 排序输出
```

### 依赖框架

- **AVFoundation**: 音视频处理
- **Vision**: 人体姿态检测
- **Accelerate (vDSP)**: FFT加速计算
- **XCTest**: 测试框架

## 📄 许可证

内部项目,仅用于 Zacks Tennis App

## 👥 贡献

如需修改算法:
1. 创建新分支
2. 运行完整测试套件
3. 确保所有验收标准通过
4. 提交 Pull Request

---

**版本**: 1.0.0
**最后更新**: 2025-11-02
**作者**: Claude Code
