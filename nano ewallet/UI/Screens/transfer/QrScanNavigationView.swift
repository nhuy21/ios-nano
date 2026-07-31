//
//  QrScanNavigationView.swift
//  nano ewallet
//
//  Wrapper NavigationStack riêng cho luồng quét QR (mở như modal trượt dọc lên từ
//  FAB, độc lập với NavigationStack của Home) — quét xong đi tiếp BankTransferAmountView
//  -> TransferSuccessView, hoặc mở "QR của tôi", tất cả nằm trong cùng 1 stack modal.
//

import SwiftUI

private enum QrFlowRoute: Hashable {
    case bankTransferAmount(BankTransferDraft)
    case transferSuccess(TransferSuccessInfo)
    case receiveQr
}

@MainActor
struct QrScanNavigationView: View {
    let onDismiss: () -> Void

    @State private var path: [QrFlowRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            QrScanView(
                onBack: onDismiss,
                onParsed: { draft in path.append(.bankTransferAmount(draft)) },
                onReceiveQr: { path.append(.receiveQr) }
            )
            .navigationDestination(for: QrFlowRoute.self) { route in
                switch route {
                case .bankTransferAmount(let draft):
                    BankTransferAmountView(
                        draft: draft,
                        onBack: { if !path.isEmpty { path.removeLast() } },
                        onSuccess: { info in path.append(.transferSuccess(info)) }
                    )
                case .transferSuccess(let info):
                    TransferSuccessView(
                        amount: info.amount, recipientName: info.recipientName,
                        recipientDetail: info.recipientDetail, noteLabel: info.noteLabel, note: info.note,
                        onHome: onDismiss
                    )
                case .receiveQr:
                    ReceiveQrView(onBack: { if !path.isEmpty { path.removeLast() } })
                }
            }
        }
    }
}
