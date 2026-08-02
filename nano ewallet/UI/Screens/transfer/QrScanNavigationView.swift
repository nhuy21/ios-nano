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
                onParsed: { draft in path.append(.bankTransfer(draft)) },
                onReceiveQr: { path.append(.receiveQr) }
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
