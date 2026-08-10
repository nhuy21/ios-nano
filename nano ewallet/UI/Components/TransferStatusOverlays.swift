//
//  TransferStatusOverlays.swift
//  nano ewallet
//
//  Hai dialog chặn màn dùng chung cho mọi luồng chuyển tiền (ví / ngân hàng / rút),
//  mirror 2 `Dialog` trong TransferScreen.kt + WalletTransferAmountScreen.kt:
//
//   - `ProcessingOverlay`: chờ Bảo Kim xử lý. PHẢI chặn thao tác (không đóng được
//     bằng chạm ra ngoài) — bấm lại nút chuyển tiền lúc đang chờ có thể tạo lệnh
//     thứ hai. Bên Android là DialogProperties(dismissOnBackPress/ClickOutside=false).
//   - `TransferErrorOverlay`: giao dịch thất bại. Phải là dialog chứ không phải dòng
//     chữ đỏ cuối form — form cuộn được nên lỗi hiện dưới đáy sẽ không ai thấy, người
//     dùng tưởng bấm nút mà không có gì xảy ra.
//

import SwiftUI

struct ProcessingOverlay: View {
    var message: String = "Đang xử lý giao dịch..."

    var body: some View {
        ZStack {
            // Không gắn onTapGesture: chạm ra ngoài KHÔNG được đóng.
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(AppColor.brand)
                    .scaleEffect(1.4)
                Text(message)
                    .font(AppFont.beVietnamPro(13.5, .medium))
                    .foregroundStyle(AppColor.payInk)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// Màn chờ của OneTouch — logo nano được "viết" dần từ trái sang rồi mờ đi, lặp lại,
/// kèm dòng trạng thái đổi theo từng bước có thật.
///
/// Vì sao lặp chứ không chạy một lần: thời gian OneTouch dao động rất rộng — ảnh QR nét,
/// mạng tốt thì xong trong ~0.4s, còn ảnh chụp tin nhắn phải OCR rồi hỏi backend mất 2–3s.
/// Animation chạy một lượt rồi dừng sẽ đứng hình giữa chừng ở ca chậm, trông như treo app.
///
/// Vì sao đổi chữ theo bước: 3 giây đứng yên một dòng chữ cũng bị đọc là treo. Mỗi bước
/// (đọc ảnh / tìm mã QR / bóc tách nội dung) tự đặt lại `message`.
struct OneTouchWaitingOverlay: View {
    var message: String = "Đang xử lý..."

    /// Một chu kỳ vẽ + mờ. Khớp `tween(2000ms)` bên Kotlin.
    private static let cycle: Double = 2.0
    /// Nét vẽ xong ở 55% chu kỳ, giữ nguyên tới 80% rồi mới mờ dần — để mắt kịp đọc logo
    /// trọn vẹn thay vì vừa hiện đủ đã tắt.
    private static let drawnAt: Double = 0.55
    private static let fadeFrom: Double = 0.8

    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 18) {
                logo
                Text(message)
                    .font(AppFont.beVietnamPro(13.5, .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    // Đổi chữ thì hiện mềm, không giật cục giữa hai bước.
                    .animation(.easeInOut(duration: 0.2), value: message)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation(.linear(duration: Self.cycle).repeatForever(autoreverses: false)) {
                progress = 1
            }
        }
    }

    private var logo: some View {
        Image("logo_white")
            .resizable()
            .scaledToFit()
            .frame(width: 132)
            .opacity(fade)
            .mask(alignment: .leading) { revealMask }
    }

    /// Dải sáng chạy từ trái sang, mép chuyển mềm 14% để trông như mực đang chảy theo nét
    /// chứ không phải thanh tiến trình có cạnh thẳng.
    private var revealMask: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: hardStop),
                    .init(color: .clear, location: softStop),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Phần đã hiện rõ hoàn toàn.
    private var hardStop: Double {
        max(0, min(1, reveal - 0.14))
    }

    /// Mép mờ. Phải LỚN HƠN `hardStop` một chút: `LinearGradient` đòi các mốc tăng dần,
    /// hai mốc bằng nhau (lúc reveal = 0) sẽ vẽ sai.
    private var softStop: Double {
        max(hardStop + 0.0001, min(1, reveal))
    }

    /// Tiến độ nét vẽ — đạt 1 (vẽ xong) ở mốc `drawnAt` rồi giữ nguyên tới hết chu kỳ.
    private var reveal: Double {
        min(1, progress / Self.drawnAt)
    }

    /// Độ mờ cuối chu kỳ. Về 0 đúng lúc chu kỳ quay lại đầu, nên vòng sau bắt đầu từ trạng
    /// thái đã trong suốt — không bị "nháy" một cái khi logo đột ngột hiện lại.
    private var fade: Double {
        guard progress > Self.fadeFrom else { return 1 }
        return 1 - (progress - Self.fadeFrom) / (1 - Self.fadeFrom)
    }
}

struct TransferErrorOverlay: View {
    let message: String
    /// Bản Kotlin của luồng ngân hàng có icon cảnh báo, luồng ví thì không — giữ
    /// nguyên khác biệt đó thay vì tự thống nhất.
    var showIcon: Bool = true
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 6) {
                if showIcon {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColor.error)
                        .padding(.bottom, 6)
                }

                Text("Giao dịch không thành công")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.payInk)

                Text(message)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Button(action: onClose) {
                    Text("ĐÓNG")
                        .font(AppFont.beVietnamPro(14, .bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppColor.brand, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 40)
        }
    }
}
