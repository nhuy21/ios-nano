//
//  HomeView.swift
//  nano ewallet
//
//  Mirror HomeScreen.kt — nối API thật (wallet/me qua WalletStore, transactions
//  qua TransactionStore), không hardcode số dư/giao dịch. Mọi hành động chưa làm
//  đều mở ComingSoonSheet thay vì im lặng.
//

import SwiftUI
import Combine
import UIKit

@MainActor
struct HomeView: View {
    @StateObject private var wallet = WalletStore.shared
    @StateObject private var transactions = TransactionStore.shared
    @StateObject private var authStore = AuthStore.shared
    @StateObject private var deepLinkStore = DeepLinkStore.shared
    @StateObject private var beneficiaryStore = BeneficiaryStore.shared

    @State private var showBalance = false
    @State private var comingSoonFeature: String?
    @State private var detailTransaction: TransactionEntity?
    @State private var path: [HomeRoute] = []
    @State private var payLinkError: String?
    @State private var showTopupWithdrawChooser = false

    private var showingComingSoon: Binding<Bool> {
        Binding(get: { comingSoonFeature != nil }, set: { if !$0 { comingSoonFeature = nil } })
    }

    var body: some View {
        NavigationStack(path: $path) {
            homeContent
                .hidesSystemNavigationBar()
                .navigationDestination(for: HomeRoute.self) { route in
                    destination(for: route)
                        .hidesSystemNavigationBar()
                }
        }
        .showsTabBar(path.isEmpty)
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
        // Dialog tuỳ biến (không dùng confirmationDialog) để giữ icon + dòng mô tả
        // như Android — menu hệ thống chỉ hiện được mỗi tiêu đề nút.
        .fullScreenCover(isPresented: $showTopupWithdrawChooser) {
            ActionChooserSheet(
                title: "Nạp/Rút ví",
                subtitle: "Chọn thao tác",
                actions: [
                    .init(
                        systemImage: "qrcode",
                        title: "Nạp tiền",
                        subtitle: "Quét mã QR để chuyển tiền vào ví",
                        handler: { path.append(.receiveQr) }
                    ),
                    .init(
                        systemImage: "building.columns",
                        title: "Rút tiền",
                        subtitle: "Chuyển tiền từ ví về tài khoản ngân hàng liên kết",
                        handler: { path.append(.withdraw) }
                    ),
                ],
                onDismiss: { showTopupWithdrawChooser = false }
            )
            .presentationBackground(.clear)
        }
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
        case .linkedBanks:
            LinkedBanksView(onBack: { if !path.isEmpty { path.removeLast() } })
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
        case .withdraw:
            WithdrawView(
                onBack: { if !path.isEmpty { path.removeLast() } },
                onSuccess: { info in path.append(.transferSuccess(info)) }
            )
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                Spacer().frame(height: 12)

                // Card lề 22, CTA lề 17 -> CTA RỘNG HƠN card mỗi bên 5pt, đúng như
                // Android (trước đây iOS để ngược: card 16, CTA 24).
                balanceCard
                    .padding(.horizontal, 22)

                topUpCta
                    .padding(.horizontal, 17)
                    // -30: CTA bo góc 26 nên phải chồng sâu hơn bán kính mới phủ kín
                    // góc bo đáy card, mirror spacedBy(-30) bên Android.
                    .padding(.top, -30)

                // Dịch vụ + Chuyển tiền nhanh + Giao dịch nằm chung MỘT nền trắng có đỉnh
                // bo cong lõm, đè lên đáy CTA — mirror WhiteTopShape bên Android, thay vì
                // ba card trắng rời nhau.
                whiteSurface
                    // Chỉ đè nhẹ vào đáy CTA: phần võng giữa của đường cong đã ăn sâu
                    // sẵn, đè thêm nhiều nữa sẽ cắt mất dòng chữ thứ hai của CTA.
                    .padding(.top, -10)
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
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
            // Danh bạ "Chuyển tiền nhanh": vẽ ngay từ cache, refresh nền — mirror
            // BeneficiaryCache.refresh() chạy song song bên Android.
            async let contactsTask: [Beneficiary] = beneficiaryStore.get()
            _ = await (walletTask, txTask, contactsTask)
        }
    }

    /// Nền trắng liền chứa 3 khối dưới — padding ngang 22, top 40 để chừa chỗ cho
    /// phần võng giữa của đường cong, mirror Column bọc trong HomeScreen.kt.
    private var whiteSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            servicesSection
            quickContactsSection
            recentTransactionsSection

            Spacer().frame(height: 140) // chừa chỗ cho floating tab bar
        }
        .padding(.horizontal, 22)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: WhiteTopShape())
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
        // Mirror cấu trúc bên Kotlin: khối nội dung và hàng 2 nút là 2 khối RIÊNG, lề
        // khác nhau (nội dung 20, nút 16) và hàng nút chừa đáy 44 — chính khoảng 44 này
        // kéo dài card xuống để CTA đè lên mà không che nút và đáy bản đồ.
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 11) {
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

                // Số ví giữ giãn cách CỐ ĐỊNH, không đổi theo bật/tắt số dư.
                balanceRow(label: "Số ví", value: wallet.bkUsername ?? "—", tracking: 3, trailing: {
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
                    // Chỉ chuỗi chấm che số dư mới cần giãn cách.
                    tracking: showBalance ? 0 : 3,
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

            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Ba nút kiểu gopay, KÉO NGANG được — mirror horizontalScroll bên Kotlin.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    pillButton(systemImage: "clock.arrow.circlepath", title: "Lịch sử") {
                        path.append(.history)
                    }
                    pillButton(systemImage: "link", title: "Liên kết") {
                        path.append(.linkedBanks)
                    }
                    // "Cấp cứu": mở danh bạ ví ở chế độ xin tiền -> chọn 1 người là vào
                    // thẳng Cuộc thoại để nhập số tiền cần xin.
                    pillButton(icon: .requestMoney, title: "Cấp cứu") {
                        path.append(.contacts)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
            }
            .padding(.top, 2)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x002A18), Color(hex: 0x023A25)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // Bản đồ Việt Nam làm watermark — độ mờ đã bake sẵn theo vùng vào ảnh
                // nên không giảm opacity ở đây. Đẩy lệch sang phải để không đè nút QR.
                GeometryReader { geo in
                    Image("vietnam_map")
                        .resizable()
                        .aspectRatio(903.0 / 1118.0, contentMode: .fit)
                        .frame(height: geo.size.height * 0.92)
                        .offset(x: 70)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Mirror boxShadow(#12813A @22%, offsetY 6, blur 14) bên Android.
        .shadow(color: Color(hex: 0x12813A).opacity(0.22), radius: 7, x: 0, y: 6)
    }

    /// Chưa có dữ liệu (chưa gọi API xong) -> "...". Có rồi mà đang ẩn -> chấm che.
    /// Đơn vị "VNĐ" luôn hiện — kể cả khi đang che số — để dòng số dư không đổi cấu
    /// trúc lúc bật/tắt.
    private var balanceText: String {
        guard let balance = wallet.balance else { return "..." }
        let amount = showBalance ? Int(balance).vndGrouped : "••••••••"
        return "\(amount) VNĐ"
    }

    @ViewBuilder
    /// `tracking` phải truyền theo từng dòng: trước đây dùng chung
    /// `showBalance ? 0 : 3` nên bật/tắt số dư kéo theo cả dãy SỐ VÍ co giãn — giãn
    /// cách đó chỉ dành cho chuỗi chấm che số dư.
    private func balanceRow<Trailing: View>(
        label: String, value: String, tracking: CGFloat, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(AppFont.beVietnamPro(15, .semibold))
                .foregroundStyle(.white)
                .tracking(tracking)
            trailing()
        }
    }

    private func pillButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        pillButton(title: title, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
    }

    /// Biến thể dùng icon vector port từ Android (nút "Cấp cứu").
    private func pillButton(
        icon: TransactionIconKind, title: String, action: @escaping () -> Void
    ) -> some View {
        pillButton(title: title, action: action) {
            TransactionIcon(kind: icon, tint: .white)
                .frame(width: 17, height: 17)
        }
    }

    private func pillButton<Icon: View>(
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            // Lề lệch trái/phải (13/9) đúng như Kotlin — icon cần thoáng hơn mũi tên.
            .padding(.leading, 13)
            .padding(.trailing, 9)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.18))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA nạp tiền

    private var topUpCta: some View {
        Button {
            // "Nạp tiền" không có màn riêng — user tự chuyển khoản vào VA hiển thị ở
            // đây, mirror Android (nút "Nạp tiền" trong dialog chooser cũng mở thẳng
            // ReceiveQrScreen).
            path.append(.receiveQr)
        } label: {
            // Cỡ chữ/icon lấy đúng theo Kotlin: tiêu đề 16 bold, phụ đề 13, icon 20,
            // mũi tên 22 — trước đây iOS để 13/11/16/13 nên cụm này nhỏ và mỏng hơn hẳn.
            HStack(spacing: 11) {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Nạp tiền nhanh, miễn phí")
                        .font(AppFont.beVietnamPro(16, .bold))
                        .foregroundStyle(.white)
                    Text("Nạp vào ví chỉ trong vài giây")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
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
                        case .walletTopup:
                            showTopupWithdrawChooser = true
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // Ô đầu LUÔN hiện dù tài khoản chưa có người nhận nào.
                    // Android dùng Icons.Default.Contacts — thẻ danh bạ có hình người bên
                    // trong, không phải icon 2 người.
                    contactItem(title: "Danh bạ", systemImage: "person.crop.rectangle.fill", isPlain: true) {
                        path.append(.contacts)
                    }

                    // Mirror `quickContacts.take(10)` bên Android.
                    ForEach(beneficiaryStore.beneficiaries.prefix(10)) { beneficiary in
                        contactAvatarItem(beneficiary)
                    }
                }
            }
        }
    }

    /// Người nhận đã lưu — avatar chữ cái, màu gán ổn định theo tên.
    private func contactAvatarItem(_ beneficiary: Beneficiary) -> some View {
        let name = beneficiary.displayName
        return Button {
            beneficiaryStore.touch(id: beneficiary.id)
            switch beneficiary.type {
            case .wallet:
                path.append(.walletTransfer(draft: WalletTransferDraft(
                    username: beneficiary.benUsername ?? "",
                    holderName: beneficiary.accName ?? name
                )))
            case .bankAccount:
                path.append(.bankTransfer(draft: BankTransferDraft(
                    bin: beneficiary.bankNo ?? "",
                    bankName: BankCache.shared.bank(bin: beneficiary.bankNo)?.shortName ?? "Ngân hàng",
                    accNo: beneficiary.accNo ?? "", accType: 0,
                    holderName: beneficiary.accName ?? name
                )))
            }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(Self.avatarColor(for: name))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(name.nameInitials)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Mirror `HomeAvatarColors` + `homeAvatarColorFor` bên Android.
    private static let avatarColors: [Color] = [
        Color(hex: 0xFFB4A2), Color(hex: 0xFFD6A5), Color(hex: 0xB5E48C), Color(hex: 0xA0C4FF),
        Color(hex: 0xBDB2FF), Color(hex: 0xFFC6FF), Color(hex: 0x9BF6FF), Color(hex: 0xFDFFB6),
    ]

    private static func avatarColor(for name: String) -> Color {
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return avatarColors[hash % avatarColors.count]
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
                            .font(.system(size: 24))
                            .foregroundStyle(isPlain ? Color(hex: 0x00A85E) : AppColor.brand)
                    }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
            }
            .frame(width: 58)
            .contentShape(Rectangle())
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

    private var initials: String { displayName.nameInitials }
}

#Preview {
    HomeView()
}
