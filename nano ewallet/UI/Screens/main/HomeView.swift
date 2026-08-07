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
import PhotosUI

@MainActor
struct HomeView: View {
    /// Ngăn xếp điều hướng do `MainTabView` SỞ HỮU, không phải `@State` của màn này.
    /// Deep link có thể tới lúc đang ở tab Cá nhân nên ngăn xếp phải sống ngoài view này.
    @Binding var path: [HomeRoute]

    /// Tab Home có đang được chọn không. BẮT BUỘC truyền vào vì `MainTabView` dùng
    /// `TabView` (để vuốt qua lại được) nên view này VẪN SỐNG khi người dùng sang tab Cá
    /// nhân — khác `switch` trước đây vốn huỷ hẳn view và mọi `.task` theo nó. Không có cờ
    /// này thì vòng poll 8s dưới đây chạy mãi ở tab khác, tốn pin và mạng vô ích.
    var isActiveTab: Bool = true

    @StateObject private var wallet = WalletStore.shared
    @StateObject private var transactions = TransactionStore.shared
    @StateObject private var authStore = AuthStore.shared
    @StateObject private var beneficiaryStore = BeneficiaryStore.shared
    @StateObject private var notifications = NotificationStore.shared

    @State private var showBalance = false
    @State private var comingSoonFeature: String?
    @State private var detailTransaction: TransactionEntity?
    @State private var showTopupWithdrawChooser = false
    @State private var showOneTouchChooser = false
    @State private var oneTouchPhoto: PhotosPickerItem?
    @State private var showOneTouchPhotoPicker = false
    @State private var isResolvingOneTouch = false
    @State private var oneTouchError: String?
    @State private var showVoiceCommand = false
    @State private var isSyncing = false
    @State private var syncError: String?
    @StateObject private var toast = ToastState()

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
        // Chỉ tab ĐANG CHỌN được quyết định thanh tab. `MainTabView` dùng `TabView` nên cả
        // hai màn cùng sống và cùng phát preference; `reduce` gộp bằng `&&` nên nếu tab kia
        // cũng phát thì Home push màn con sẽ ẩn luôn thanh tab của tab Cá nhân.
        .showsTabBar(isActiveTab ? path.isEmpty : true)
        // Rời tab -> pop hết về màn gốc. `TabView` giữ view sống nên `path` vẫn còn nguyên;
        // không dọn thì vuốt từ tab Cá nhân về đây sẽ rơi vào ĐÚNG màn con đang treo dở,
        // chứ không phải Trang chủ. Vuốt qua lại luôn là gốc <-> gốc.
        //
        // An toàn với deep link: `openOnHome` set `selectedTab = .home` TRƯỚC khi append,
        // nên lúc route được đẩy vào thì `isActiveTab` đã là true — nhánh này không chạy.
        .onChangeNewCompat(of: isActiveTab) { active in
            if !active { path.removeAll() }
        }
        // Deep link (pay link / push xin tiền) KHÔNG quan sát ở đây — xem MainTabView.
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
            .transparentSheetBackground()
        }
        // OneTouch — chọn nguồn nội dung, mirror dialog PasteSourceRow bên Kotlin.
        .fullScreenCover(isPresented: $showOneTouchChooser) {
            ActionChooserSheet(
                title: "OneTouch",
                subtitle: "Chọn nguồn nội dung chuyển khoản",
                actions: [
                    .init(
                        systemImage: "doc.on.clipboard",
                        title: "Dán từ bộ nhớ tạm",
                        subtitle: "Nội dung hoặc ảnh đã copy",
                        handler: { Task { await runOneTouch { await OneTouchResolver.resolveClipboard() } } }
                    ),
                    .init(
                        systemImage: "photo.on.rectangle",
                        title: "Chọn ảnh trong thư viện",
                        subtitle: "Ảnh QR hoặc ảnh chụp tin nhắn CK",
                        handler: { showOneTouchPhotoPicker = true }
                    ),
                ],
                onDismiss: { showOneTouchChooser = false }
            )
            .transparentSheetBackground()
        }
        .photosPicker(isPresented: $showOneTouchPhotoPicker, selection: $oneTouchPhoto, matching: .images)
        .onChangeNewCompat(of: oneTouchPhoto) { item in
            guard let item else { return }
            oneTouchPhoto = nil
            Task {
                await runOneTouch {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        return .failure("Không đọc được ảnh")
                    }
                    return await OneTouchResolver.resolve(image: image)
                }
            }
        }
        .overlay { if isResolvingOneTouch { ProcessingOverlay(message: "Đang nhận diện...") } }
        .fullScreenCover(isPresented: $showVoiceCommand) {
            VoiceCommandOverlay(
                onDismiss: { showVoiceCommand = false },
                onResolved: { route in
                    showVoiceCommand = false
                    // Nghe ra người nhận -> vào THẲNG màn nhập tiền (ví hay ngân hàng do
                    // overlay quyết định theo loại danh bạ), số tiền điền sẵn nếu bóc được.
                    // Vẫn phải xác nhận + PIN nên không tự chuyển tiền.
                    path.append(route)
                }
            )
            .transparentSheetBackground()
        }
        .alert("Không nhận diện được", isPresented: oneTouchErrorBinding) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(oneTouchError ?? "")
        }
        .alert("Đồng bộ ví thất bại", isPresented: syncErrorBinding) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(syncError ?? "")
        }
        // 30pt tính từ MÉP TRÊN của thanh tab, không phải từ đáy màn: thanh tab nổi được vẽ
        // SAU HomeView trong ZStack của MainTabView nên nó đè lên toast, đặt 30pt từ đáy là
        // bị che kín. Cộng theo hằng số của MainTabView để đổi chiều cao thanh tab không
        // làm lệch chỗ này.
        .toast(toast, bottomPadding: MainTabView.floatingBarTotalHeight + 300)
    }

    private var syncErrorBinding: Binding<Bool> {
        Binding(get: { syncError != nil }, set: { if !$0 { syncError = nil } })
    }

    private var oneTouchErrorBinding: Binding<Bool> {
        Binding(get: { oneTouchError != nil }, set: { if !$0 { oneTouchError = nil } })
    }

    /// Chạy một lượt OneTouch rồi đưa kết quả tới đúng màn.
    private func runOneTouch(_ resolve: () async -> OneTouchResult) async {
        guard !isResolvingOneTouch else { return }
        isResolvingOneTouch = true
        defer { isResolvingOneTouch = false }

        switch await resolve() {
        case .bank(let draft):
            path.append(.bankTransfer(draft: draft))
        case .wallet(let draft):
            path.append(.walletTransferAmount(draft))
        case .failure(let message):
            oneTouchError = message
        }
    }

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .history:
            HistoryView(onBack: { if !path.isEmpty { path.removeLast() } })
        case .notifications:
            NotificationsView(
                onClose: { if !path.isEmpty { path.removeLast() } },
                onOpenConversation: { bkUsername in
                    path.append(.conversation(otherName: "", otherBkUsername: bkUsername))
                }
            )
        case .linkedBanks:
            LinkedBanksView(onBack: { if !path.isEmpty { path.removeLast() } })
        case .contacts(let filter):
            ContactsView(
                onBack: { if !path.isEmpty { path.removeLast() } },
                filterType: filter,
                // Chọn từ danh bạ = người nhận đã xác thực -> vào THẲNG màn nhập số tiền.
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
                    path.append(.walletTransferAmount(WalletTransferDraft(username: username, holderName: name)))
                },
                onPickForRequest: { name, bkUsername in
                    path.append(.conversation(otherName: name, otherBkUsername: bkUsername))
                }
            )
        case .bankTransfer(let draft):
            BankTransferView(
                onBack: { if !path.isEmpty { path.removeLast() } },
                onHome: { path.removeAll() },
                initialDraft: draft,
                onSuccess: { info in path.append(.transferSuccess(info)) },
                onOpenContacts: { path.append(.contacts(filter: .bankAccount)) }
            )
        // Hai route, MỘT màn: luồng chuyển ví giờ gộp số ví + số tiền + lời nhắn vào cùng
        // màn. `.walletTransfer(nil)` = nhập tay, có draft = người nhận đã khoá.
        case .walletTransfer(let draft):
            WalletTransferAmountView(
                draft: draft,
                onBack: { if !path.isEmpty { path.removeLast() } },
                onSuccess: { info in path.append(.transferSuccess(info)) },
                onOpenContacts: { path.append(.contacts(filter: .wallet)) },
                onHome: { path.removeAll() }
            )
        case .walletTransferAmount(let draft):
            WalletTransferAmountView(
                draft: draft,
                onBack: { if !path.isEmpty { path.removeLast() } },
                onSuccess: { info in path.append(.transferSuccess(info)) },
                onHome: { path.removeAll() }
            )
        case .transferSuccess(let info):
            TransferSuccessView(info: info, onHome: { path.removeAll() })
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

    /// Check số dư trước; chỉ khi THẬT SỰ đổi (có tiền vào/ra) mới gọi tiếp giao dịch +
    /// thông báo — tránh 2 request thừa mỗi lần kéo-refresh nếu không có gì mới.
    /// Không còn poll tự động theo thời gian — chỉ chạy khi user chủ động kéo xuống, hoặc
    /// lúc Home vừa mở (`.task` ở `homeContent`).
    private func reloadWalletData() async {
        let balanceBefore = wallet.balance
        await wallet.refresh(force: true)
        guard wallet.balance != balanceBefore else { return }
        async let txTask: Void = transactions.refreshRecent()
        async let notifTask: Bool = notifications.refresh()
        _ = await (txTask, notifTask)
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
                    // -80 ăn đúng vào 81 điểm nối thêm ở đáy CTA (mirror spacedBy(-80)
                    // bên Android): phủ kín phần nền xanh dôi ra, chừa lại 1 điểm nên
                    // không thấy khe hở mà cũng không cắt vào dòng chữ của CTA.
                    .padding(.top, -80)
            }
        }
        // Kéo xuống để làm mới thủ công — không còn poll tự động theo thời gian, chỉ
        // dựa vào push (APNs/FCM) + hành động chủ động này để cập nhật số dư/giao dịch/
        // thông báo khi đang ở Home.
        .refreshable { await reloadWalletData() }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        .screenBackground(Color(hex: 0xF3F5F7))
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
            // Badge chuông phải đúng ngay khi mở Home, không đợi nhịp poll kế tiếp.
            async let notifTask: Bool = notifications.refresh()
            _ = await (walletTask, txTask, contactsTask, notifTask)
        }
        // Tải trước model nhận diện giọng nói on-device (chỉ iOS 26+). `.task` RIÊNG, không gộp
        // vào khối trên: lần đầu tải mất vài giây tới vài chục giây tuỳ mạng, gộp chung sẽ giữ
        // các request mà UI cần ngay (số dư, giao dịch) chờ theo.
        .task {
            await SpeechRecognizerService.prewarmModel()
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

            iconButton(systemImage: "mic.fill") { showVoiceCommand = true }

            ZStack(alignment: .topTrailing) {
                Button {
                    path.append(.notifications)
                } label: {
                    TransactionIcon(kind: .notificationBell, tint: AppColor.payInk)
                        .frame(width: 18, height: 18)
                        .frame(width: 42, height: 42)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                // Chấm đỏ chỉ hiện khi CÓ thông báo chưa đọc thật — trước đây vẽ cứng
                // nên lúc nào cũng đỏ, người dùng không phân biệt được có gì mới hay không.
                if notifications.unreadCount > 0 {
                    Text(notifications.unreadCount > 9 ? "9+" : "\(notifications.unreadCount)")
                        .font(AppFont.beVietnamPro(10, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(AppColor.error, in: Capsule())
                        .offset(x: 2, y: -2)
                }
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
                                .font(AppFont.beVietnamPro(15, .bold))
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
                        .font(AppFont.beVietnamPro(12, .semibold))
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
                            // Không có phản hồi thì người dùng không biết đã copy được chưa
                            // nên bấm lại nhiều lần. Chuỗi khớp Android ("Đã sao chép số ví").
                            toast.show("Đã sao chép số ví")
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
                    // Đối soát trực tiếp với Bảo Kim — nặng hơn refresh thường (BE phải
                    // gọi sang Bảo Kim) nên chỉ chạy khi user chủ động bấm.
                    pillButton(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: isSyncing ? "Đang đồng bộ" : "Đồng bộ",
                        isLoading: isSyncing
                    ) {
                        syncWallet()
                    }
                    pillButton(systemImage: "link", title: "Liên kết") {
                        path.append(.linkedBanks)
                    }
                    // "Cấp cứu": mở danh bạ ví ở chế độ xin tiền -> chọn 1 người là vào
                    // thẳng Cuộc thoại để nhập số tiền cần xin.
                    pillButton(icon: .requestMoney, title: "Cấp cứu") {
                        path.append(.contacts(filter: .wallet))
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

    /// `isLoading`: nút là HÀNH ĐỘNG (vd "Đồng bộ") -> đổi mũi tên thành spinner và chặn
    /// bấm lại. Mặc định `false` = nút điều hướng, giữ nguyên mũi tên như Kotlin.
    private func pillButton(
        systemImage: String,
        title: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        pillButton(title: title, isLoading: isLoading, action: action) {
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
        isLoading: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                Text(title)
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .lineLimit(1)
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.7)
                        // Khớp bề rộng chỗ mũi tên chiếm để nút không co giật khi đổi trạng thái.
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
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
        .disabled(isLoading)
    }

    /// Đối soát ví với Bảo Kim. Kéo lại cả giao dịch gần đây vì BE có thể vừa ghi bản ghi
    /// đối soát cho phần số dư lệch.
    private func syncWallet() {
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            if let message = await wallet.syncWithBaoKim() {
                syncError = message
                return
            }
            await transactions.refreshRecent()
        }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Kéo đáy dải xanh dài thêm 81 để nền trắng đè lên mà không hở — mirror
        // `padding(bottom = 81.dp)` bên Android. Vùng nối thêm CHỈ là nền, không bấm
        // được (nút chỉ bọc phần chữ ở trên), nên bấm vào chỗ trống không mở màn nạp tiền.
        .padding(.bottom, 81)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [AppColor.brand, Color(hex: 0x00934F)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        // Bóng theo đúng Kotlin: xanh rất tối, lệch dọc nhỏ, blur rộng — toả quanh hai
        // bên CTA. Dùng màu brand như trước thì bóng nhạt và không thấy CTA nổi lên.
        .shadow(color: Color(hex: 0x012E1D).opacity(0.48), radius: 9, x: 0, y: 3)
    }

    // MARK: - Dịch vụ (quick actions)

    /// Nhãn nhỏ nổi trên icon dịch vụ — mirror khối badge trong HomeScreen.kt.
    private struct ServiceBadge {
        let text: String
        let icon: TransactionIconKind
        /// Bàn tay có nhịp nhấn xuống/thả ra; icon gió để tĩnh (giống Android).
        var animated = false
    }

    private struct ServiceItem: Identifiable {
        let id = UUID()
        let title: String
        let icon: TransactionIconKind
        var badge: ServiceBadge?
    }

    /// Icon đúng thứ tự + hình dạng bản gốc Android (SERVICES trong HomeScreen.kt):
    /// ic_bank_transfer, ic_transfer_arrows, ic_paste_ck, ic_wallet_topup.
    private let services: [ServiceItem] = [
        .init(
            title: "Chuyển tiền ngân hàng",
            icon: .bankTransfer,
            badge: .init(text: "như gió", icon: .wind)
        ),
        .init(title: "Chuyển tiền", icon: .transferArrows),
        .init(
            title: "OneTouch",
            icon: .pasteCk,
            badge: .init(text: "một chạm", icon: .tapHand, animated: true)
        ),
        .init(title: "Nạp/Rút ví", icon: .walletTopup),
    ]

    /// Viên nhãn xanh: CHỮ trước, ICON sau (đúng thứ tự bản Android).
    private func serviceBadge(_ badge: ServiceBadge) -> some View {
        HStack(spacing: 2) {
            Text(badge.text)
                .font(AppFont.beVietnamPro(8, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if badge.animated {
                TapHandBadgeIcon()
            } else {
                TransactionIcon(kind: badge.icon, tint: .white)
                    .frame(width: 9, height: 9)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(AppColor.brand, in: Capsule())
        // Nhãn chỉ để nhìn — không chặn chạm, nếu không nó ăn mất phần trên của nút.
        .allowsHitTesting(false)
    }

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
                        case .pasteCk:
                            showOneTouchChooser = true
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
                                // Nhãn nhô LÊN KHỎI ô icon nên phải là overlay không bị
                                // clip: đặt trong `VStack` sẽ đẩy icon xuống và lệch hàng.
                                .overlay(alignment: .top) {
                                    if let badge = service.badge {
                                        serviceBadge(badge)
                                            .offset(y: -9)
                                    }
                                }
                            Text(service.title)
                                .font(AppFont.beVietnamPro(11))
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

    /// 10 người nhận hay dùng nhất: ưu tiên SỐ LẦN chuyển, hoà thì lấy người chuyển GẦN ĐÂY
    /// hơn. Trước đây lấy thẳng thứ tự BE trả (theo ngày tạo) nên người mới thêm mà chưa
    /// chuyển bao giờ vẫn đứng trên người chuyển hàng tuần.
    private var quickContacts: [Beneficiary] {
        beneficiaryStore.beneficiaries
            .sorted { lhs, rhs in
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                // `lastUsedAt` là ISO-8601 nên so chuỗi cũng ra đúng thứ tự thời gian.
                // Chưa dùng lần nào (`nil`) xếp sau cùng.
                return (lhs.lastUsedAt ?? "") > (rhs.lastUsedAt ?? "")
            }
            .prefix(10)
            .map { $0 }
    }

    private var quickContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chuyển tiền nhanh")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.payInk)
                Spacer()
                Button("Xem tất cả") {
                    path.append(.contacts(filter: nil))
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
                        path.append(.contacts(filter: nil))
                    }

                    ForEach(quickContacts) { beneficiary in
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
            // Người nhận đã lưu trong danh bạ nên thông tin đã đủ và đã xác thực —
            // vào THẲNG màn nhập số tiền, bỏ qua bước chọn/nhập người nhận.
            switch beneficiary.type {
            case .wallet:
                path.append(.walletTransferAmount(WalletTransferDraft(
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
                            .font(AppFont.beVietnamPro(16, .bold))
                            .foregroundStyle(.white)
                    }
                Text(name)
                    .font(AppFont.beVietnamPro(11, .medium))
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
                    .font(AppFont.beVietnamPro(11, .medium))
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
                        .font(AppFont.beVietnamPro(11))
                        .foregroundStyle(AppColor.payMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(signedAmount(for: tx))
                        .font(AppFont.beVietnamPro(13, .semibold))
                        .foregroundStyle(TransactionDisplay.amountColor(for: tx))
                    Text(formattedTime(tx.createdAt))
                        .font(AppFont.beVietnamPro(11))
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
        if Calendar.app.isDateInToday(date) {
            return DateFormatter.app("HH:mm").string(from: date)
        }
        if Calendar.app.isDateInYesterday(date) {
            return "Hôm qua"
        }
        return DateFormatter.app("dd/MM").string(from: date)
    }

    // MARK: - Derived

    private var displayName: String {
        authStore.userFullName ?? "Người dùng"
    }

    private var initials: String { displayName.nameInitials }
}

/// Bàn tay trong nhãn "một chạm" — nhấn xuống rồi thả, nghỉ, lặp lại. Mirror `TapHandIcon`
/// bên Android (chu kỳ 1300ms, thu nhỏ 22% và trôi xuống 3pt lúc nhấn).
///
/// Không dùng `KeyframeAnimator` (iOS 17, cao hơn deployment target): tự hẹn nhịp bằng
/// `Timer` rồi bật/tắt một cờ, mỗi chiều một `withAnimation` riêng — nhấn nhanh, thả chậm
/// hơn, giống đường keyframe gốc hơn là một animation đối xứng.
private struct TapHandBadgeIcon: View {
    @State private var pressed = false

    /// Chu kỳ 1.3s: nghỉ 0.25 -> nhấn (0.18) -> thả (0.23) -> nghỉ phần còn lại.
    private static let cycle: TimeInterval = 1.3
    private static let restBeforePress: TimeInterval = 0.25
    private static let pressDuration: TimeInterval = 0.18
    private static let releaseDuration: TimeInterval = 0.23

    var body: some View {
        TransactionIcon(kind: .tapHand, tint: .white)
            .frame(width: 10, height: 10)
            .scaleEffect(pressed ? 0.78 : 1)
            .offset(y: pressed ? 1.25 : 0)
            .task {
                // Vòng lặp gắn với `task`: view biến mất là task bị huỷ, không để lại
                // Timer chạy ngầm như `Timer.scheduledTimer` sẽ làm.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(Self.restBeforePress * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: Self.pressDuration)) { pressed = true }

                    try? await Task.sleep(nanoseconds: UInt64(Self.pressDuration * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: Self.releaseDuration)) { pressed = false }

                    let elapsed = Self.restBeforePress + Self.pressDuration + Self.releaseDuration
                    try? await Task.sleep(nanoseconds: UInt64((Self.cycle - elapsed) * 1_000_000_000))
                }
            }
    }
}

#Preview {
    HomeView(path: .constant([]))
}
