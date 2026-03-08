import SwiftUI
import Testing
@testable import Zacks网球视频剪辑

struct RallyPlayerLayoutTests {
    @Test("横屏紧凑高度下优先保留核心按钮")
    func compactLandscapePrioritizesPrimaryActions() {
        let layout = RallyPlayerOverlayLayout(
            containerSize: CGSize(width: 844, height: 390),
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        )

        #expect(layout.isCompactHeight)
        #expect(layout.showsSecondaryActions == false)
        #expect(layout.actionButtonSpacing < 20)
        #expect(layout.bottomInfoBottomPadding(hasProgressBar: true) > layout.progressBarBottomPadding + layout.progressBarBaseHeight)
    }

    @Test("竖屏保留完整操作列")
    func portraitKeepsFullActionStack() {
        let layout = RallyPlayerOverlayLayout(
            containerSize: CGSize(width: 390, height: 844),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )

        #expect(layout.isCompactHeight == false)
        #expect(layout.showsSecondaryActions)
        #expect(layout.actionButtonSpacing >= 20)
        #expect(layout.bottomInfoBottomPadding(hasProgressBar: false) >= 80)
    }

    @Test("横屏但高度充足时保留完整操作列")
    func roomyLandscapeKeepsSecondaryActions() {
        let layout = RallyPlayerOverlayLayout(
            containerSize: CGSize(width: 932, height: 500),
            safeAreaInsets: EdgeInsets(top: 0, leading: 32, bottom: 21, trailing: 32)
        )

        #expect(layout.isLandscape)
        #expect(layout.isCompactHeight == false)
        #expect(layout.showsSecondaryActions)
        #expect(layout.showsMetadataChips)
        #expect(layout.descriptionLineLimit == 2)
    }

    @Test("进度条段高基于当前容器高度计算")
    func progressSegmentHeightUsesContainerHeight() {
        let compactLayout = RallyPlayerOverlayLayout(
            containerSize: CGSize(width: 844, height: 390),
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        )
        let regularLayout = RallyPlayerOverlayLayout(
            containerSize: CGSize(width: 390, height: 844),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )

        let compactHeight = compactLayout.progressSegmentHeight(for: 6)
        let regularHeight = regularLayout.progressSegmentHeight(for: 6)

        #expect(compactHeight >= 4)
        #expect(regularHeight <= 20)
        #expect(compactHeight < regularHeight)
    }
}
