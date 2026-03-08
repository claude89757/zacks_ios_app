import SwiftUI

struct RallyPlayerOverlayLayout {
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets

    var isLandscape: Bool {
        containerSize.width > containerSize.height
    }

    var isCompactHeight: Bool {
        containerSize.height <= 430
    }

    var showsSecondaryActions: Bool {
        !isCompactHeight
    }

    var showsMetadataChips: Bool {
        !isCompactHeight
    }

    var topBarTopPadding: CGFloat {
        safeAreaInsets.top + (isCompactHeight ? 8 : 16)
    }

    var leadingOverlayPadding: CGFloat {
        max(16, safeAreaInsets.leading + 12)
    }

    var trailingOverlayPadding: CGFloat {
        max(16, safeAreaInsets.trailing + 12)
    }

    var actionColumnTrailingPadding: CGFloat {
        trailingOverlayPadding
    }

    var actionColumnBottomPadding: CGFloat {
        safeAreaInsets.bottom + (isCompactHeight ? 56 : 128)
    }

    var actionButtonSpacing: CGFloat {
        isCompactHeight ? 12 : 20
    }

    var actionIconSize: CGFloat {
        isCompactHeight ? 24 : 28
    }

    var actionControlSize: CGFloat {
        isCompactHeight ? 38 : 44
    }

    var progressBarBottomPadding: CGFloat {
        safeAreaInsets.bottom + (isCompactHeight ? 10 : 24)
    }

    var progressBarBaseHeight: CGFloat {
        28
    }

    private var baseBottomInfoBottomPadding: CGFloat {
        safeAreaInsets.bottom + (isCompactHeight ? 12 : 84)
    }

    func bottomInfoBottomPadding(hasProgressBar: Bool) -> CGFloat {
        guard hasProgressBar else {
            return baseBottomInfoBottomPadding
        }

        let gap = isCompactHeight ? 8.0 : 12.0
        let progressReservedHeight = progressBarBottomPadding + progressBarBaseHeight + gap
        return max(baseBottomInfoBottomPadding, progressReservedHeight)
    }

    var bottomInfoReservedTrailingWidth: CGFloat {
        showsSecondaryActions ? 120 : 84
    }

    var descriptionLineLimit: Int {
        isCompactHeight ? 1 : 2
    }

    var progressIndicatorVerticalPadding: CGFloat {
        isCompactHeight ? 72 : 120
    }

    func progressSegmentHeight(for count: Int) -> CGFloat {
        let visibleCount = max(count, 1)
        let reservedHeight = safeAreaInsets.top + safeAreaInsets.bottom + (isCompactHeight ? 180 : 300)
        let totalHeight = max(40, containerSize.height - reservedHeight)
        let spacing = CGFloat(max(visibleCount - 1, 0)) * 3
        let segmentHeight = (totalHeight - spacing) / CGFloat(visibleCount)
        let maxSegmentHeight = isCompactHeight ? 16.0 : 20.0
        return max(4, min(segmentHeight, maxSegmentHeight))
    }
}
