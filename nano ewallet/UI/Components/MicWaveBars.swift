//
//  MicWaveBars.swift
//  nano ewallet
//
//  Thanh sóng báo "đang nghe" — mirror `AmtMicWaveBars` bên Kotlin: 7 vạch dọc nảy
//  so le nhau, mỗi vạch trễ 75ms so với vạch trước, một vòng 1040ms.
//

import SwiftUI

struct MicWaveBars: View {
    var barCount = 7
    var height: CGFloat = 44
    var color: Color = AppColor.brand

    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: height)
                    .scaleEffect(y: animating ? 1 : 0.15, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.52)
                            .repeatForever(autoreverses: true)
                            // Trễ dần theo chỉ số -> sóng chạy ngang thay vì cả 7 vạch
                            // nảy cùng lúc.
                            .delay(Double(index) * 0.075),
                        value: animating
                    )
            }
        }
        .frame(height: height)
        .onAppear { animating = true }
    }
}
