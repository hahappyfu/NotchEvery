//
//  NotchHeaderView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        HStack {
            NotchTabBar(
                zones: NotchViewModel.zoneOrder,
                current: vm.contentType,
                onJump: { vm.jumpToZone($0) }
            )
            Spacer()
            Button {
                vm.jumpToZone(.settings)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        // 空白顶栏点击 = 下一区（与右滑同语义）：tab/齿轮是 Button 会优先消费，落到这里的才是空白处；
        // 此前在全局 mouseDown 里做会跟 Button 打架（先切走重建按钮再吞 mouseUp），故搬到视图层
        .contentShape(Rectangle())
        .onTapGesture { vm.nextZone() }
        .animation(vm.animation, value: vm.contentType)
        .font(.system(.headline, design: .rounded))
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}
