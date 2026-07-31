//
//  HomeView.swift
//  nano ewallet
//
//  Mirror HomeScreen.kt — nối API thật (wallet/me qua WalletStore, transactions
//  qua TransactionStore), không hardcode số dư/giao dịch. Mọi hành động chưa làm
//  đều mở ComingSoonSheet thay vì im lặng.
//

import SwiftUI
import UIKit

@MainActor
struct HomeView: View {
    @StateObject private var wallet = WalletStore.shared
    @StateObject private var transactions = TransactionStore.shared
    @StateObject private var authStore = AuthStore.shared
    @StateObject private var deepLinkStore = DeepLinkStore.shared

    @State private var showBalance = false
    @State private var comingSoonFeature: String?
    @State private var detailTransaction: TransactionEntity?
    @State private var path: [HomeRoute] = []
    @State private var payLinkError: String?

    private var showingComingSoon: Binding<Bool> {
        Binding(get: { comingSoonFeature != nil }, set: { if !$0 { comingSoonFeature = nil } })
    }

    var body: some View {
        NavigationStack(path: $path) {
            homeContent
                .navigationDestination(for: HomeRoute.self) { route in
                    destination(for: route)
                }
        }
        .onChange(of: deepLinkStore.pendingConversationBkUsername, initial: true) { _, value in
            guard let bkUsername = value else { return }
            _ = deepLinkStore.consumeConversation()
            path.append(.conversation(otherName: "", otherBkUsername: bkUsername))
        }
        .onChange(of: deepLinkStore.pendingPayToken, initial: true) { _, value in
            guard let token = value else { return }
            _ = deepLinkStore.consumePayToken()
            Task { await resolvePayLink(token: token) }
        }
        .alert(
            "Không mở được link nhận tiền", isPresented: payLinkErrorBinding,
            actions: { Button("Đóng", role: .cancel) {} },
            message: { Text(payLinkError ?? "") }
        )
    }

    private var payLinkErrorBinding: Binding<Bool> {
        Binding(get: { payLinkError != nil }, set: { if !$0 { payLinkError = nil } })
    }

    /// App tự động điền (prefill) trực tiếp vào màn chuyển khoản có sẵn sau khi resolve
    /// — mirror MainActivity.kt: KHÔNG có màn "xác nhận thanh toán qua link" riêng.
    private func resolvePayLink(token: String) async {
        do {
            let info = try await PayLinkService.resolve(reqToken: token)
            switch info.payKind {
            case .bank:
                guard let accNo = info.accNo, let bankNo = info.bankNo else {
                    payLinkError = "Link nhận tiền không hợp lệ"
                    return
                }
                let bankName = BankCache.shared.bank(bin: bankNo)?.shortName ?? info.bankShortName ?? "Ngân hàng"
                path.append(.bankTransferAmount(BankTransferDraft(
                    bin: bankNo, bankName: bankName, accNo: accNo, accType: 0,
                    holderName: info.accName ?? "Người nhận",
                    prefillAmount: info.amountValue, prefillContent: info.note,
                    amountEditable: info.amountValue == nil,
                    contentEditable: (info.note?.isEmpty ?? true),
                    payLinkToken: token
                )))
            case .wallet:
                guard let benUsername = info.benUsername else {
                    payLinkError = "Link nhận tiền không hợp lệ"
                    return
                }
                path.append(.walletTransferAmount(WalletTransferDraft(
                    username: benUsername, holderName: info.accName ?? benUsername, payLinkToken: token
                )))
            }
        } catch let error as APIError {
            payLinkError = error.message
        } catch {
            payLinkError = "Không mở được link nhận tiền"
        }
    }

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .history:
            HistoryView(onBack: { if !path.isEmpty { path.removeLast() } })
        case .contacts:
            ContactsView(
                onBack: { if !path.isEmpty { path.removeLast() } },
                onPickForTransfer: { beneficiary in
                    path.append(.bankTransfer(draft: BankTransferDraft(
                        bin: beneficiary.bankNo ?? "",
                        bankName: BankCache.shared.bank(bin: beneficiary.bankNo)?.shortName ?? "Ngân hàng",
                        accNo: beneficiary.accNo ?? "", accType: 0,
                        holderName: beneficiary.accName ?? beneficiary.displayName
                    )))
                },
                onPickForWalletTransfer: { name, sub in
                    let username = sub.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    path.append(.walletTransfer(draft: WalletTransferDraft(username: username, holderName: name)))
                },
                onPickForRequest: { name, bkUsername in
                    path.append(.conversation(otherName: name, otherBkUsername: bkUsername))
                }
            )
        case .bankTransfer(let draft):
            BankTransferView(
                onBack: { if !path.isEmpty { path.removeLast() } },
                initialDraft: draft,
                onContinue: { draft in path.append(.bankTransferAmount(draft)) },
                onOpenContacts: { path.append(.contacts) }
            )
        case .walletTransfer(let draft):
            WalletTransferView(
                onBack: { if !path.isEmpty { path.removeLast() } },
                initialDraft: draft,
                onContinue: { draft in path.append(.walletTransferAmount(draft)) }
            )
        case .bankTransferAmount(let draft):
            BankTransferAmountView(
                draft: draft,
                onBack: { if !path.isEmpty { path.removeLast() } },
                onSuccess: { info in path.append(.transferSuccess(info)) }
            )
        case .walletTransferAmount(let draft):
            WalletTransferAmountView(
                draft: draft,
                onBack: { if !path.isEmpty { path.removeLast() } },
                onSuccess: { info in path.append(.transferSuccess(info)) }
            )
        case .transferSuccess(let info):
            TransferSuccessView(
                amount: info.amount, recipientName: info.recipientName,
                recipientDetail: info.recipientDetail, noteLabel: info.noteLabel, note: info.note,
                onHome: { path.removeAll() }
            )
        case .conversation(let otherName, let otherBkUsername):
            ConversationView(
                otherName: otherName, otherBkUsername: otherBkUsername,
                onBack: { if !path.isEmpty { path.removeLast() } }
            )
        case .receiveQr:
            ReceiveQrView(onBack: { if !path.isEmpty { path.removeLast() } })
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                Spacer().frame(height: 12)

                balanceCard
                    .padding(.horizontal, 16)

                topUpCta
                    .padding(.horizontal, 24)
                    .padding(.top, -18) // đè lên mép dưới balance card, mirror overlap âm bên Android

                Spacer().frame(height: 24)

                servicesSection
                    .padding(.horizontal, 16)

                Spacer().frame(height: 24)

                quickContactsSection
                    .padding(.horizontal, 16)

                Spacer().frame(height: 24)

                recentTransactionsSection
                    .padding(.horizontal, 16)

                Spacer().frame(height: 140) // chừa chỗ cho floating tab bar
            }
        }
        .background(Color(hex: 0xF3F5F7))
        .comingSoonSheet(isPresented: showingComingSoon, feature: comingSoonFeature ?? "Tính năng")
        .sheet(item: $detailTransaction) { tx in
            TransactionDetailSheet(tx: tx, onDismiss: { detailTransaction = nil })
        }
        .task {
            // Home luôn revalidate số dư (force: true) — mirror WalletCache.refresh
            // được gọi lại mỗi lần vào Home bên Android, không "trúng cache là thôi".
            async let walletTask: Void = wallet.refresh(force: true)
            async let txTask: Void = transactions.refreshRecent()
            _ = await (walletTask, txTask)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("logo_main")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)

            Spacer()

            iconButton(systemImage: "mic.fill") { comingSoonFeature = "Trợ lý giọng nói" }

            ZStack(alignment: .topTrailing) {
                Button {
                    comingSoonFeature = "Thông báo"
                } label: {
                    TransactionIcon(kind: .notificationBell, tint: AppColor.payInk)
                        .frame(width: 18, height: 18)
                        .frame(width: 42, height: 42)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Circle()
                    .fill(AppColor.error)
                    .frame(width: 8, height: 8)
                    .offset(x: -2, y: 2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private func iconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(AppColor.payInk)
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Balance card

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColor.brand, Color(hex: 0x00723A)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(initials)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text(displayName.uppercased())
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    path.append(.receiveQr)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode")
                        Text("QR")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            balanceRow(label: "Số ví", value: wallet.bkUsername ?? "—", trailing: {
                if wallet.bkUsername != nil {
                    Button {
                        UIPasteboard.general.string = wallet.bkUsername
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            })

            balanceRow(
                label: "Số dư",
                value: balanceText,
                trailing: {
                    Button {
                        showBalance.toggle()
                    } label: {
                        Image(systemName: showBalance ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            )

            HStack(spacing: 10) {
                pillButton(systemImage: "clock.arrow.circlepath", title: "Lịch sử") {
                    path.append(.history)
                }
                pillButton(systemImage: "link", title: "Liên kết") {
                    comingSoonFeature = "Liên kết ngân hàng"
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x002A18), Color(hex: 0x023A25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Chưa có dữ liệu (chưa gọi API xong) -> "...". Có rồi mà đang ẩn -> chấm che.
    private var balanceText: String {
        guard let balance = wallet.balance else { return "..." }
        return showBalance ? Int(balance).vndFormatted : "••••••••"
    }

    @ViewBuilder
    private func balanceRow<Trailing: View>(
        label: String, value: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(AppFont.beVietnamPro(15, .semibold))
                .foregroundStyle(.white)
                .tracking(showBalance ? 0 : 3)
            trailing()
        }
    }

    private func pillButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 13))
                Text(title).font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 10))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.18))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA nạp tiền

    private var topUpCta: some View {
        Button {
            comingSoonFeature = "Nạp / Rút ví"
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Nạp tiền nhanh, miễn phí")
                        .font(AppFont.beVietnamPro(13, .semibold))
                        .foregroundStyle(.white)
                    Text("Nạp vào ví chỉ trong vài giây")
                        .font(AppFont.beVietnamPro(11))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [AppColor.brand, Color(hex: 0x00934F)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: AppColor.brand.opacity(0.3), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dịch vụ (quick actions)

    private struct ServiceItem: Identifiable {
        let id = UUID()
        let title: String
        let icon: TransactionIconKind
    }

    /// Icon đúng thứ tự + hình dạng bản gốc Android (SERVICES trong HomeScreen.kt):
    /// ic_bank_transfer, ic_transfer_arrows, ic_paste_ck, ic_wallet_topup.
    private let services: [ServiceItem] = [
        .init(title: "Chuyển tiền ngân hàng", icon: .bankTransfer),
        .init(title: "Chuyển tiền", icon: .transferArrows),
        .init(title: "OneTouch", icon: .pasteCk),
        .init(title: "Nạp/Rút ví", icon: .walletTopup),
    ]

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dịch vụ")
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(AppColor.payInk)

            HStack(spacing: 0) {
                ForEach(services) { service in
                    Button {
                        switch service.icon {
                        case .bankTransfer:
                            path.append(.bankTransfer(draft: nil))
                        case .transferArrows:
                            path.append(.walletTransfer(draft: nil))
                        default:
                            comingSoonFeature = service.title
                        }
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: 0xF5F7F6))
                                .frame(width: 52, height: 52)
                                .overlay {
                                    TransactionIcon(kind: service.icon, tint: Color(hex: 0x12A150))
                                        .frame(width: 22, height: 22)
                                }
                            Text(service.title)
                                .font(.system(size: 11))
                                .foregroundStyle(AppColor.payInk)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(height: 28)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Chuyển tiền nhanh

    private var quickContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chuyển tiền nhanh")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.payInk)
                Spacer()
                Button("Xem tất cả") {
                    path.append(.contacts)
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.brand)
            }

            // TODO (Phase kế tiếp): hiện vài danh bạ dùng gần đây thay vì chỉ ô "Danh bạ"
            // cố định — cần BeneficiaryStore.beneficiaries đã sort theo lastUsedAt.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    contactItem(title: "Danh bạ", systemImage: "person.2.fill", isPlain: true) {
                        path.append(.contacts)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func contactItem(
        title: String, systemImage: String, isPlain: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(isPlain ? Color(hex: 0xF5F7F6) : AppColor.brandSoft)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 18))
                            .foregroundStyle(isPlain ? AppColor.payMuted : AppColor.brand)
                    }
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
            }
            .frame(width: 58)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Giao dịch gần đây

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Giao dịch gần đây")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.payInk)
                Spacer()
                Button("Xem tất cả") {
                    path.append(.history)
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.brand)
            }
            .padding(.bottom, 8)

            if transactions.isLoading && transactions.recentTransactions.isEmpty {
                Text("Đang tải...")
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else if let error = transactions.loadError, transactions.recentTransactions.isEmpty {
                Text(error)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.error)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else if transactions.recentTransactions.isEmpty {
                Text("Chưa có giao dịch")
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(transactions.recentTransactions.enumerated()), id: \.element.id) { index, tx in
                    if index > 0 {
                        Rectangle()
                            .fill(Color(hex: 0xECECEC))
                            .frame(height: 1)
                            .padding(.leading, 42)
                    }
                    transactionRow(tx)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func transactionRow(_ tx: TransactionEntity) -> some View {
        let icon = TransactionDisplay.iconStyle(for: tx)
        return Button {
            detailTransaction = tx
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(icon.background)
                    .frame(width: 30, height: 30)
                    .overlay {
                        TransactionIcon(kind: icon.icon, tint: icon.tint)
                            .frame(width: 16, height: 16)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(TransactionDisplay.listTitle(for: tx))
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.payInk)
                        .lineLimit(2)
                    Text(subtitle(for: tx))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.payMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(signedAmount(for: tx))
                        .font(AppFont.beVietnamPro(13, .semibold))
                        .foregroundStyle(TransactionDisplay.amountColor(for: tx))
                    Text(formattedTime(tx.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.payMuted)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for tx: TransactionEntity) -> String {
        if let benBankName = tx.benBankName, let benAccNo = tx.benAccNo {
            return "\(benBankName) •• \(String(benAccNo.suffix(4)))"
        }
        return tx.description ?? "Ví nano"
    }

    private func signedAmount(for tx: TransactionEntity) -> String {
        let signed = tx.isIncome ? tx.amountValue : -tx.amountValue
        return Int(signed).vndSigned
    }

    private func formattedTime(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter.standard.date(from: iso) else {
            return iso
        }
        if Calendar.current.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Hôm qua"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: date)
    }

    // MARK: - Derived

    private var displayName: String {
        authStore.userFullName ?? "Người dùng"
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        guard let last = parts.last else { return "?" }
        return String(last.prefix(1)).uppercased()
    }
}

#Preview {
    HomeView()
}
