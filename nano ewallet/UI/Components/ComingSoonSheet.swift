//
//  ComingSoonSheet.swift
//  nano ewallet
//
//  Dùng cho MỌI nút/route chưa phát triển ở phase hiện tại — bấm vào hiện sheet này
//  thay vì im lặng hoặc crash. Xoá dần khi từng tính năng được implement thật.
//

import SwiftUI

struct ComingSoonSheet: View {
    var feature: String = "Tính năng"
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Image(systemName: "hammer.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppColor.brand)
                .frame(width: 64, height: 64)
                .background(AppColor.brandSoft)
                .clipShape(Circle())
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text("\(feature) đang phát triển")
                    .font(AppFont.beVietnamPro(17, .bold))
                    .foregroundStyle(AppColor.payInk)

                Text("Tính năng này sẽ sớm ra mắt trong bản cập nhật tiếp theo.")
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Button {
                onDismiss()
            } label: {
                Text("Đã hiểu")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColor.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .presentationDetents([.height(320)])
        // Sheet không set nền sẽ lấy nền hệ thống — ở dark mode là ĐEN, mà chữ trong đây
        // đều là màu tối cố định (`payInk`/`payMuted`) nên bị dìm gần như không đọc được.
        // Ghim nền sáng cho khớp Android (bên đó nền sheet là `Color.White` cứng).
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .presentationDragIndicator(.hidden)
    }
}

/// Gắn vào bất kỳ View nào để bấm phát ra sheet "chưa phát triển" — tránh lặp
/// `@State private var showComingSoon` ở từng nơi gọi.
struct ComingSoonModifier: ViewModifier {
    @Binding var isPresented: Bool
    var feature: String = "Tính năng"

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ComingSoonSheet(feature: feature) { isPresented = false }
        }
    }
}

extension View {
    func comingSoonSheet(isPresented: Binding<Bool>, feature: String = "Tính năng") -> some View {
        modifier(ComingSoonModifier(isPresented: isPresented, feature: feature))
    }
}
