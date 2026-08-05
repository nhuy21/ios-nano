//
//  TransactionIcon.swift
//  nano ewallet
//
//  Port chính xác 12 icon vector vẽ tay từ flash-wallet/app/src/main/res/drawable/*.xml
//  (không phải Material Icons — không có SF Symbol tương đương chính xác) bằng
//  SVGPath. Mỗi icon giữ đúng pathData/viewBox/stroke gốc, chỉ đổi màu qua tint
//  (đúng cách Android tint 1 màu khi dùng — màu gốc trong file XML không quan trọng).
//

import SwiftUI

/// Icon giao dịch/dịch vụ — vẽ lại từ path Android, luôn tint theo `tint`.
enum TransactionIconKind {
    case bankTransfer       // ic_bank_transfer — toà nhà ngân hàng (Material account_balance)
    case moneyReceive       // ic_money_receive — vòng tròn + mũi tên vào + $
    case moneySend          // ic_money_send — vòng tròn + mũi tên ra + $
    case refund             // ic_refund — vòng cung xoay ngược + $
    case saveMoney          // ic_save_money — Hugeicons Save Money Dollar
    case withdrawArrow      // ic_withdraw_arrow — vòng tròn + mũi tên chéo ra
    case txnFailed          // ic_txn_failed — vòng tròn cảnh báo dấu chấm than
    case walletTopup        // ic_wallet_topup — thẻ + dấu chấm (contactless)
    case transferArrows     // ic_transfer_arrows — thẻ + 2 mũi tên chuyển
    case requestMoney       // ic_request_money — bàn tay hứng đồng xu $
    case pasteCk            // ic_paste_ck — clipboard đặc
    case notificationBell   // ic_notification_bell — chuông thông báo
    case wind               // ic_wind — 3 luồng gió, dùng cho badge "như gió"
    case tapHand            // ic_tap_hand — bàn tay chạm, dùng cho badge "một chạm"
}

struct TransactionIcon: View {
    let kind: TransactionIconKind
    var tint: Color = .primary

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(spec.strokes.enumerated()), id: \.offset) { _, stroke in
                    SVGPath(pathData: stroke, viewBox: spec.viewBox)
                        .stroke(
                            tint,
                            style: StrokeStyle(
                                lineWidth: spec.strokeWidth * (size / spec.viewBox.width),
                                lineCap: .round, lineJoin: .round
                            )
                        )
                }
                ForEach(Array(spec.fills.enumerated()), id: \.offset) { _, fill in
                    SVGPath(pathData: fill, viewBox: spec.viewBox)
                        .fill(tint, style: FillStyle(eoFill: spec.evenOddFill))
                }
            }
            .frame(width: size, height: size)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var spec: IconSpec { kind.spec }
}

/// Dữ liệu path gốc từng icon — tách khỏi View để dễ đối chiếu ngược với file .xml Android.
private struct IconSpec {
    var viewBox: CGSize
    var strokes: [String] = []
    var fills: [String] = []
    var strokeWidth: CGFloat = 1.5
    var evenOddFill: Bool = false
}

private extension TransactionIconKind {
    var spec: IconSpec {
        switch self {
        case .bankTransfer:
            // Material "account_balance" — path fill tuyệt đối, viewBox 24.
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                fills: ["M4,10v7h3v-7H4zM10,10v7h3v-7H10zM2,22h19v-3H2V22zM16,10v7h3v-7H16zM11.5,1L2,6v2h19V6L11.5,1z"]
            )

        case .moneyReceive:
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                strokes: [
                    "M14 2.222q-.97-.198-2-.2c-5.523 0-10 4.472-10 9.989S6.477 22 12 22s10-4.472 10-9.989q-.002-1.027-.2-1.998",
                    "M12 9.014c-1.105 0-2 .671-2 1.499c0 .827.895 1.498 2 1.498s2 .67 2 1.498s-.895 1.499-2 1.499m0-5.994c.87 0 1.612.417 1.886 1m-1.886-1v-.999m0 6.993c-.87 0-1.612-.417-1.886-1m1.886 1v.999",
                    "M21.995 2L17.82 6.174m-.824-3.653l.118 3.088c0 .728.435 1.182 1.228 1.239l3.124.147",
                ],
                strokeWidth: 1.5
            )

        case .moneySend:
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                strokes: [
                    "M14 2.2q-.97-.198-2-.2C6.477 2 2 6.477 2 12s4.477 10 10 10s10-4.477 10-10q-.002-1.03-.2-2",
                    "M12 9c-1.105 0-2 .672-2 1.5s.895 1.5 2 1.5s2 .672 2 1.5s-.895 1.5-2 1.5m0-6c.87 0 1.612.417 1.886 1M12 9V8m0 7c-.87 0-1.612-.417-1.886-1M12 15v1",
                    "m16.998 7.002l4.176-4.178m.824 3.656l-.118-3.09c0-.729-.435-1.183-1.228-1.24l-3.124-.147",
                ],
                strokeWidth: 1.5
            )

        case .refund:
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                strokes: [
                    "M12 2a10 10 0 1 0 7 2.929",
                    "M19.5 2v4.5H15",
                    "M12 8.5v7M14.2 10c0-.966-.985-1.75-2.2-1.75s-2.2.784-2.2 1.75c0 .966.985 1.75 2.2 1.75s2.2.784 2.2 1.75c0 .966-.985 1.75-2.2 1.75s-2.2-.784-2.2-1.75",
                ],
                strokeWidth: 1.5
            )

        case .saveMoney:
            return IconSpec(
                viewBox: CGSize(width: 26, height: 25),
                strokes: [
                    "M21.3905,13.5417C22.1513,12.4902 22.6105,11.2645 22.7221,9.9881C22.8336,8.7117 22.5935,7.4295 22.0259,6.2707C21.4582,5.1119 20.5832,4.1173 19.4887,3.387C18.3942,2.6567 17.119,2.2166 15.7914,2.1108C14.4638,2.0051 13.1306,2.2375 11.9261,2.7846C10.7216,3.3318 9.6882,4.1744 8.9301,5.2276C8.1719,6.2809 7.7156,7.5075 7.6072,8.7842C7.4988,10.0609 7.742,11.3425 8.3125,12.5",
                    "M15.1667,6.2502C13.9696,6.2502 13,6.9502 13,7.8127C13,8.6752 13.9696,9.3752 15.1667,9.3752C16.3638,9.3752 17.3333,10.0752 17.3333,10.9377C17.3333,11.8002 16.3638,12.5002 15.1667,12.5002M15.1667,6.2502C16.1092,6.2502 16.913,6.6845 17.2098,7.2918M15.1667,6.2502V5.2085M15.1667,12.5002C14.2242,12.5002 13.4203,12.0658 13.1235,11.4585M15.1667,12.5002V13.5418",
                    "M3.25,14.5835H5.8446C6.1631,14.5835 6.4773,14.6522 6.7622,14.7856L8.9743,15.8147C9.2593,15.947 9.5734,16.0158 9.893,16.0158H11.0218C12.1138,16.0158 13,16.8397 13,17.8564C13,17.8981 12.9707,17.9335 12.9285,17.945L10.1757,18.6772C9.6818,18.8085 9.1551,18.7625 8.6938,18.5481L6.3288,17.4481M13,17.1877L17.9757,15.7179C18.4089,15.5901 18.873,15.5971 19.3018,15.738C19.7306,15.8788 20.1021,16.1463 20.3634,16.5022C20.7632,17.0335 20.6007,17.796 20.0178,18.1189L11.8766,22.6366C11.622,22.7782 11.3401,22.8686 11.0481,22.902C10.7561,22.9355 10.46,22.9115 10.1779,22.8314L3.25,20.8543",
                ],
                strokeWidth: 1.5
            )

        case .withdrawArrow:
            return IconSpec(
                viewBox: CGSize(width: 20, height: 20),
                strokes: [
                    "M10.7083,10.5417L17.0833,4.16669M17.0833,7.95202V4.16669H13.2979",
                    "M9.99996,4.16669C6.08783,4.16669 2.91663,7.3379 2.91663,11.25C2.91663,15.1621 6.08783,18.3334 9.99996,18.3334C13.9121,18.3334 17.0833,15.1621 17.0833,11.25",
                ],
                strokeWidth: 1.5
            )

        case .txnFailed:
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                strokes: [
                    "M12 22c5.523 0 10 -4.477 10 -10S17.523 2 12 2S2 6.477 2 12s4.477 10 10 10Z",
                    "M12 7.5v6",
                ],
                fills: ["M12 17.25m-1.1,0a1.1,1.1 0,1 1,2.2 0a1.1,1.1 0,1 1,-2.2 0"],
                strokeWidth: 1.5
            )

        case .walletTopup:
            // Placeholder gốc bên Android cũng ghi rõ "chờ icon thật" — dùng tạm path
            // đó (thẻ tín dụng + chấm NFC), giữ nguyên vì đây là ý đồ có chủ đích
            // của bản gốc, không phải thiếu sót khi port.
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                fills: [
                    "M21,7.28V5c0,-1.1 -0.9,-2 -2,-2H5c-1.11,0 -2,0.9 -2,2v14c0,1.1 0.89,2 2,2h14c1.1,0 2,-0.9 2,-2v-2.28c0.59,-0.35 1,-0.98 1,-1.72V9c0,-0.74 -0.41,-1.37 -1,-1.72zM20,9v6h-7V9h7zM5,19V5h14v2h-6c-1.1,0 -2,0.9 -2,2v6c0,1.1 0.9,2 2,2h6v2H5z",
                    "M16,13.5c0.83,0 1.5,-0.67 1.5,-1.5s-0.67,-1.5 -1.5,-1.5 -1.5,0.67 -1.5,1.5 0.67,1.5 1.5,1.5z",
                ]
            )

        case .transferArrows:
            return IconSpec(
                viewBox: CGSize(width: 48, height: 48),
                strokes: [
                    "M8,6 H28 A4,4 0 0 1 32,10 V22 A4,4 0 0 1 28,26 H8 A4,4 0 0 1 4,22 V10 A4,4 0 0 1 8,6 Z",
                    "M8,19 H17",
                    "M14,31 H43 M38.5,26.5 L43,31 L38.5,35.5",
                    "M43,40 H14 M18.5,35.5 L14,40 L18.5,44.5",
                ],
                fills: ["M4,13 V10 A4,4 0 0 1 8,6 H28 A4,4 0 0 1 32,10 V13 Z"],
                strokeWidth: 3
            )

        case .requestMoney:
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                strokes: [
                    "M19.745 13a7 7 0 1 0-12.072-1",
                    "M14 6c-1.105 0-2 0.672-2 1.5S12.895 9 14 9s2 0.672 2 1.5s-0.895 1.5-2 1.5m0-6c0.87 0 1.612 0.417 1.886 1M14 6V5m0 7c-0.87 0-1.612-0.417-1.886-1M14 12v1",
                    "M3 14h2.395c0.294 0 0.584 0.066 0.847 0.194l2.042 0.988c0.263 0.127 0.553 0.193 0.848 0.193h1.042c1.008 0 1.826 0.791 1.826 1.767c0 0.04 -0.027 0.074 -0.066 0.085l-2.541 0.703a1.95 1.95 0 0 1 -1.368 -0.124L5.842 16.75M12 16.5l4.593 -1.411a1.985 1.985 0 0 1 2.204 0.753c0.369 0.51 0.219 1.242 -0.319 1.552l-7.515 4.337a2 2 0 0 1 -1.568 0.187L3 20.02",
                ],
                strokeWidth: 1.5
            )

        case .pasteCk:
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                fills: ["M6.268 3A2 2 0 0 1 8 2h5a2 2 0 0 1 1.732 1H16a2 2 0 0 1 2 2v4h1a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-8a2 2 0 0 1-2-2v-1H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM6 5H5v12h4v-6a2 2 0 0 1 2-2h5V5h-1a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2m5 6v9h8v-9zm2-7H8v1h5z"],
                evenOddFill: true
            )

        case .notificationBell:
            return IconSpec(
                viewBox: CGSize(width: 21, height: 21),
                strokes: [
                    "M5.25,7.875C5.25,6.48261 5.80312,5.14726 6.78769,4.16269C7.77226,3.17812 9.10761,2.625 10.5,2.625C11.8924,2.625 13.2277,3.17812 14.2123,4.16269C15.1969,5.14726 15.75,6.48261 15.75,7.875C15.75,12.25 17.5,13.125 17.5,13.125H3.5C3.5,13.125 5.25,12.25 5.25,7.875Z",
                    "M8.75,16.625C8.75,17.0891 8.93437,17.5342 9.26256,17.8624C9.59075,18.1906 10.0359,18.375 10.5,18.375C10.9641,18.375 11.4092,18.1906 11.7374,17.8624C12.0656,17.5342 12.25,17.0891 12.25,16.625",
                ],
                strokeWidth: 1.575
            )

        // ic_wind — path FILL kiểu evenOdd (3 luồng gió), viewBox 24.
        case .wind:
            return IconSpec(
                viewBox: CGSize(width: 24, height: 24),
                fills: [
                    "M6.25 5.5A3.25 3.25 0 1 1 9.5 8.75H3a.75.75 0 0 1 0-1.5h6.5A1.75 1.75 0 1 0 7.75 5.5v.357a.75.75 0 1 1-1.5 0zm8 2a4.25 4.25 0 1 1 4.25 4.25H2a.75.75 0 0 1 0-1.5h16.5a2.75 2.75 0 1 0-2.75-2.75V8a.75.75 0 0 1-1.5 0zm-11 6.5a.75.75 0 0 1 .75-.75h14.5a4.25 4.25 0 1 1-4.25 4.25V17a.75.75 0 0 1 1.5 0v.5a2.75 2.75 0 1 0 2.75-2.75H4a.75.75 0 0 1-.75-.75",
                ],
                evenOddFill: true
            )

        // ic_tap_hand — path STROKE, viewBox 48 (khác các icon khác dùng 24).
        case .tapHand:
            return IconSpec(
                viewBox: CGSize(width: 48, height: 48),
                strokes: [
                    "M37 44H17.476a.26.26 0 0 1-.218-.121L7.86 28.727a4.095 4.095 0 1 1 7.011-4.23l2.462 4.194V7.942a3.942 3.942 0 0 1 7.884 0v9.329c0 .585.465 1.066 1.05 1.085l11.621.388A2.185 2.185 0 0 1 40 20.928V41a3 3 0 0 1-3 3",
                ],
                strokeWidth: 4
            )
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            TransactionIcon(kind: .bankTransfer, tint: .blue).frame(width: 32, height: 32)
            TransactionIcon(kind: .moneyReceive, tint: .green).frame(width: 32, height: 32)
            TransactionIcon(kind: .moneySend, tint: .red).frame(width: 32, height: 32)
            TransactionIcon(kind: .refund, tint: .indigo).frame(width: 32, height: 32)
        }
        HStack(spacing: 16) {
            TransactionIcon(kind: .saveMoney, tint: .orange).frame(width: 32, height: 32)
            TransactionIcon(kind: .withdrawArrow, tint: .purple).frame(width: 32, height: 32)
            TransactionIcon(kind: .txnFailed, tint: .red).frame(width: 32, height: 32)
            TransactionIcon(kind: .walletTopup, tint: .brown).frame(width: 32, height: 32)
        }
        HStack(spacing: 16) {
            TransactionIcon(kind: .transferArrows, tint: .green).frame(width: 32, height: 32)
            TransactionIcon(kind: .requestMoney, tint: .black).frame(width: 32, height: 32)
            TransactionIcon(kind: .pasteCk, tint: .black).frame(width: 32, height: 32)
            TransactionIcon(kind: .notificationBell, tint: .black).frame(width: 32, height: 32)
        }
    }
    .padding()
}
