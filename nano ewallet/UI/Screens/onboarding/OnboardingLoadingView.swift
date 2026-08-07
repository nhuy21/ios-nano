//
//  OnboardingLoadingView.swift
//  nano ewallet
//
//  Mirror `OnboardingLoadingScreen` trong FixEkycFieldsScreen.kt — màn chờ khi đang gọi
//  `onboarding/create-agreement`. Bảo Kim cần 2-5 phút xử lý ví nên phải có màn chờ tử tế
//  chứ không để người dùng nhìn spinner suông.
//
//  Thanh tiến trình CỐ TÌNH không chạy tới 100%: bò từ 0 lên 90% trong 150 giây rồi đứng
//  yên. Chạm 100% mà vẫn đang chờ thì người dùng tưởng xong rồi mà màn không đổi.
//

import SwiftUI

struct OnboardingLoadingView: View {

    var message: String = "Đang chuẩn bị thoả thuận mở ví..."

    private static let frames = ["running1", "running2", "running3", "running4"]
    private static let freezeSeconds: Double = 150
    private static let maxProgress: Double = 0.9

    @State private var frameIndex = 0
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Image("logo_green")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 30)
                .padding(.top, 20)

            Spacer(minLength: 0)

            Image(Self.frames[frameIndex])
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 190, height: 190)

            Text(message)
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)
                .multilineTextAlignment(.center)
                .padding(.top, 36)

            Text("Bạn cứ thong thả, mọi thứ đang được chuẩn bị.")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            progressBar
                .padding(.top, 28)

            Spacer(minLength: 0)

            Text("Quá trình này thường mất 2–3 phút")
                .font(AppFont.beVietnamPro(12.5))
                .foregroundStyle(AppColor.payMuted)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
        .screenBackground(Color.white, alignment: .center)
        .task { await runFrameLoop() }
        .task { await runProgress() }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.brandSoft)
                Capsule()
                    .fill(AppColor.brand)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 6)
    }

    /// Đổi khung ~7 hình/giây cho ra dáng đang chạy.
    private func runFrameLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 140_000_000)
            frameIndex = (frameIndex + 1) % Self.frames.count
        }
    }

    private func runProgress() async {
        let step: Double = 0.1
        var elapsed: Double = 0
        while elapsed < Self.freezeSeconds, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
            elapsed += step
            progress = min(elapsed / Self.freezeSeconds * Self.maxProgress, Self.maxProgress)
        }
        progress = Self.maxProgress
    }
}

#Preview {
    OnboardingLoadingView()
}
