//
//  QrScanNavigationView.swift
//  nano ewallet
//
//  Wrapper NavigationStack riêng cho luồng quét QR (mở như modal trượt dọc lên từ
//  FAB, độc lập với NavigationStack của Home) — quét xong đi tiếp BankTransferView
//  (thẻ người nhận đã khoá) -> TransferSuccessView, hoặc mở "QR của tôi", tất cả
//  nằm trong cùng 1 stack modal.
//

import SwiftUI

private enum QrFlowRoute: Hashable {
    case bankTransfer(BankTransferDraft)
    case walletTransferAmount(WalletTransferDraft)
    case transferSuccess(TransferSuccessInfo)
    case receiveQr
}

@MainActor
struct QrScanNavigationView: View {
    let onDismiss: () -> Void
    /// "Cấp cứu ví tui" — đóng modal QR rồi mở danh bạ trên tab Home, thay vì dựng
    /// lại cả luồng chọn người nhận + cuộc thoại bên trong ngăn xếp QR.
    var onEmergency: () -> Void = {}

    @State private var path: [QrFlowRoute] = []

    /// Màn QR đã kéo xuống bao nhiêu trong lúc đang vuốt — chỉ để phản hồi thị giác, buông
    /// tay là về 0 hoặc đóng hẳn.
    @State private var dragOffset: CGFloat = 0

    /// Kéo quá mốc này thì đóng, chưa tới thì bật về. 120pt đủ xa để không đóng oan khi
    /// người dùng chỉ chạm trượt tay trên khung ngắm.
    private static let dismissThreshold: CGFloat = 120

    var body: some View {
        NavigationStack(path: $path) {
            QrScanView(
                onBack: onDismiss,
                onParsed: { draft in path.append(.bankTransfer(draft)) },
                onReceiveQr: { path.append(.receiveQr) },
                onEmergency: onEmergency,
                onWalletRecipient: { draft in path.append(.walletTransferAmount(draft)) },
                // Ngăn xếp rỗng = màn quét đang ở trên cùng. Đây là tín hiệu để nó mở lại
                // việc quét sau khi người dùng back từ màn chuyển tiền.
                isActive: path.isEmpty
            )
            .hidesSystemNavigationBar()
            .navigationDestination(for: QrFlowRoute.self) { route in
                qrDestination(for: route)
                    .hidesSystemNavigationBar()
            }
        }
        .offset(y: dragOffset)
        // Kéo từ trên xuống để đóng — modal này mở bằng `fullScreenCover` nên KHÔNG có cử
        // chỉ đóng sẵn như `sheet`.
        //
        // Chỉ gắn khi `path.isEmpty`, tức đang ở đúng màn quét: các màn con là nhập số tiền
        // / nội dung, kéo tay một cái mà đóng cả luồng thì mất hết những gì vừa gõ.
        .gesture(path.isEmpty ? dismissDragGesture : nil)
    }

    /// Chỉ nhận kéo XUỐNG, và chỉ khi quãng dọc lớn hơn quãng ngang — bỏ qua kéo lên/ngang
    /// để không ăn tranh thao tác khác trên màn quét (chạm lấy nét, hai lần chạm về Home).
    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > Self.dismissThreshold {
                    onDismiss()
                    // Trả offset về 0 sau khi đóng, nếu không lần mở lại sẽ hiện màn đã bị
                    // đẩy lệch xuống.
                    dragOffset = 0
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    @ViewBuilder
    private func qrDestination(for route: QrFlowRoute) -> some View {
        switch route {
        // Back ở hai màn chuyển tiền ĐÓNG HẲN luồng QR thay vì lùi về màn quét: quét xong là
        // đã có người nhận rồi, quay lại quét tiếp gần như không phải ý người dùng — họ bấm
        // back là muốn thoát. Muốn quét mã khác thì mở lại từ nút QR ở thanh tab.
        case .bankTransfer(let draft):
            BankTransferView(
                onBack: onDismiss,
                onHome: onDismiss,
                initialDraft: draft,
                onSuccess: { info in path.append(.transferSuccess(info)) }
            )
            // Nút back đã đóng cả luồng, cử chỉ vuốt phải theo cho nhất quán — không chặn
            // thì vuốt vẫn lùi được về màn quét.
            .disablesSwipeBack()
        case .walletTransferAmount(let draft):
            WalletTransferAmountView(
                draft: draft,
                onBack: onDismiss,
                onSuccess: { info in path.append(.transferSuccess(info)) },
                onHome: onDismiss
            )
            .disablesSwipeBack()
        case .transferSuccess(let info):
            TransferSuccessView(info: info, onHome: onDismiss)
        case .receiveQr:
            ReceiveQrView(onBack: { if !path.isEmpty { path.removeLast() } })
        }
    }
}
