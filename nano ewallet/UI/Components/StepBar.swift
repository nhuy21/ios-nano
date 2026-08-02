//
//  StepBar.swift
//  nano ewallet
//
//  Mirror ui/components/StepBar.kt — 3 chặng onboarding có nhãn: Thông tin → Xác thực
//  → Hoàn tất. Khác `OtpStepBar` (3 vạch phẳng, riêng của màn OTP) — Android cũng giữ
//  hai bản tách biệt.
//

import SwiftUI

struct StepBar: View {
    /// Đếm từ 1.
    let step: Int
    var activeColor: Color = .white
    var inactiveColor: Color = Color.white.opacity(0.4)
    var checkTint: Color = Color(hex: 0x1A4DB8)

    private let labels = ["Thông tin", "Xác thực", "Hoàn tất"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let stepNumber = index + 1
                let isDone = stepNumber < step
                let isActive = stepNumber == step

                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(isDone || isActive ? activeColor : .clear)
                        Circle()
                            .strokeBorder(isDone || isActive ? activeColor : inactiveColor, lineWidth: 2)

                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(checkTint)
                        } else {
                            Text("\(stepNumber)")
                                .font(AppFont.beVietnamPro(isActive ? 13 : 11, .bold))
                                .foregroundStyle(isActive ? checkTint : inactiveColor)
                        }
                    }
                    .frame(width: isActive ? 28 : 22, height: isActive ? 28 : 22)

                    Text(label)
                        .font(AppFont.beVietnamPro(10, isActive ? .semibold : .regular))
                        .foregroundStyle(isActive || isDone ? activeColor : inactiveColor)
                        .fixedSize()
                }

                if index < labels.count - 1 {
                    Rectangle()
                        .fill(isDone ? activeColor : inactiveColor)
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                        // Đường nối căn theo tâm vòng tròn, không theo tâm cả cụm — cụm
                        // có nhãn bên dưới nên tâm cụm thấp hơn tâm vòng tròn.
                        .padding(.bottom, 18)
                }
            }
        }
    }
}

#Preview {
    StepBar(step: 2, activeColor: AppColor.brand, inactiveColor: AppColor.payMuted.opacity(0.35), checkTint: .white)
        .padding()
}
