import SwiftUI

/// 分段选项卡条：黑色滑动胶囊跟随选中项，可点直跳
struct NotchTabBar: View {
    let zones: [NotchViewModel.ContentType]
    let current: NotchViewModel.ContentType
    let onJump: (NotchViewModel.ContentType) -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(zones, id: \.self) { zone in
                Button {
                    onJump(zone)
                } label: {
                    Label {
                        Text(zone.tabTitleKey)
                    } icon: {
                        Image(systemName: zone == .normal ? "chart.pie.fill" : "gearshape.fill")
                            .font(.system(size: 11))
                    }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(zone == current ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if zone == current {
                                Capsule()
                                    .fill(Color.black.opacity(0.55))
                                    .matchedGeometryEffect(id: "tabpill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
        )
    }
}
