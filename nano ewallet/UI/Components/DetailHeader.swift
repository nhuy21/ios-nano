//
//  DetailHeader.swift
//  nano ewallet
//
//  Header dùng chung cho các màn con điều hướng từ Settings — mirror bố cục lặp lại
//  ở SecurityScreen/ChangeSecretScreen/PinLimitScreen/DevicesScreen/LinkedBanksScreen/
//  TermsOfUseScreen bên Android: back tròn (nền trắng, shadow nhẹ) + title bold.
//

import SwiftUI

struct DetailHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .circleButtonShadow()
            .accessibilityLabel("Quay lại")

            Text(title)
                .font(AppFont.beVietnamPro(20, .bold))
                .foregroundStyle(AppColor.payInk)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
