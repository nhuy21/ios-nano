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

    var body: some View {
        NavigationStack(path: $path) {
            QrScanView(
                onBack: onDismiss,
                onParsed: { draft in path.append(.bankTransfer(draft)) },
                onReceiveQr: { path.append(.receiveQr) },
                onEmergency: onEmergency,
                onWalletRecipient: { draft in path.append(.walletTransferAmount(draft)) }
            )
            .hidesSystemNavigationBar()
            .navigationDestination(for: QrFlowRoute.self) { route in
                qrDestination(for: route)
                    .hidesSystemNavigationBar()
            }
        }
    }

    @ViewBuilder
    private func qrDestination(for route: QrFlowRoute) -> some View {
        switch route {
        case .bankTransfer(let draft):
            BankTransferView(
                onBack: { if !path.isEmpty { path.removeLast() } },
                onHome: onDismiss,
                initialDraft: draft,
                onSuccess: { info in path.append(.transferSuccess(info)) }
            )
        case .walletTransferAmount(let draft):
            WalletTransferAmountView(
                draft: draft,
                onBack: { if !path.isEmpty { path.removeLast() } },
                onSuccess: { info in path.append(.transferSuccess(info)) }
            )
        case .transferSuccess(let info):
            TransferSuccessView(info: info, onHome: onDismiss)
        case .receiveQr:
            ReceiveQrView(onBack: { if !path.isEmpty { path.removeLast() } })
        }
    }
}
