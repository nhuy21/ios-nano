//
//  PrivacyScreenOverlay.swift
//  nano ewallet
//
//  Che kín màn hình khi app rời foreground (background/inactive) — iOS chụp ảnh y hệt
//  màn hình đang hiển thị để làm thẻ preview App Switcher NGAY tại khoảnh khắc đó, không
//  hỏi ý app. Không che thì preview lộ số dư/số tài khoản/giao dịch thật cho bất kỳ ai
//  đang cầm máy đã mở khóa, kể cả không mở app — chỉ cần vuốt lên xem App Switcher.
//
//  `.inactive` (không chỉ `.background`) BẮT BUỘC phải che: iOS chụp ảnh preview ngay khi
//  chuyển sang inactive (vd lúc vừa bấm Home, trước khi kịp sang background), che muộn hơn
//  là ảnh đã chụp xong.
//

import SwiftUI

struct PrivacyScreenOverlay: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if scenePhase != .active {
            AppColor.brand
                .ignoresSafeArea()
                .overlay {
                    Image("logo_main")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                }
                .transition(.identity)
        }
    }
}
