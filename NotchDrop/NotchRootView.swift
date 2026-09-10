//
//  NotchRootView.swift
//  NotchDrop
//
import SwiftUI

/// 520 双页外壳：滑动切页 + dots + 右上齿轮（设置 Popover 在任务 6 接）。
struct NotchRootView: View {
    @StateObject var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {                pages
                Button {
                    vm.showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .popover(isPresented: $vm.showSettings, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        NotchMenuView(vm: vm)
                        NotchSettingsView(vm: vm)
                        Text("NotchEvery \(appVersion)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(minWidth: 360)
                }
            }
            SmoothPageIndicator(pageCount: 2, currentPage: Binding(
                get: { NotchViewModel.pageIndex(for: vm.contentType) },
                set: { vm.jumpToZone(NotchViewModel.zone(for: $0)) }
            ))
        }
        // 刘海安全区垫在测量区内：测量含安全区，面板才够高（03 工单）
        .padding(.top, vm.notchSafeAreaTop)
        // 整体上报：含安全区+内容+dots，dots 预留魔法数不再需要
        .zoneSizeReporter(active: true)
        .frame(width: vm.zoneOpenedSize.width)
    }

    private var pages: some View {
        ZStack(alignment: .topLeading) {
            switch vm.contentType {
            case .normal:
                OverviewPageView(vm: vm)
                    // 量理想宽：maxWidth 填充会让测量值永远等于容器宽、宽度锁死，
                    // 水平 fixedSize 让面板宽度收敛到内容（垂直保持 flexible）
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(reduceMotion ? .opacity : (vm.lastSwipeDirection == .next ? .zoneSlideNext : .zoneSlidePrevious))
            case .token:
                TokenZoneView()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(reduceMotion ? .opacity : (vm.lastSwipeDirection == .next ? .zoneSlideNext : .zoneSlidePrevious))
            }
        }
        // 切页专用快弹簧（清单 05；裁剪已撤：与窗口边双边打架是闪的根因，窗口自带裁剪 enough）
        .animation(vm.pageAnimation, value: vm.contentType)
    }
}
