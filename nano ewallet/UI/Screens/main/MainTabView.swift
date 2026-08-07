//
//  MainTabView.swift
//  nano ewallet
//
//  Mirror MainScreen.kt — KHÔNG dùng TabView chuẩn vì Android là 1 floating pill
//  navbar custom với FAB QR nhô lên giữa. Chỉ 2 trang thật: Home (index 0) +
//  Settings (index 4 bên Android, ở đây gọi .settings) — 3 tab còn lại
//  (Financial/QrScanTab/History) KHÔNG dùng, mirror đúng theo khảo sát.
//
//  Mép trên pill dùng DomeTopShape: nhô 1 gò tròn ôm lấy nút QR thành khối liền
//  mạch, thay vì nút nổi rời trên mép bar phẳng.
//

import SwiftUI

struct MainTabView: View {
    enum Tab { case home, settings }

    @State private var selectedTab: Tab = .home
    /// FAB QR mở như modal trượt dọc lên (mirror transition QR_SCAN bên Android),
    /// không push vào NavigationStack riêng của Home/Settings.
    @State private var showQrScan = false
    /// Chỉ hiện thanh tab ở màn gốc Home/Settings — các màn con push lên thì ẩn.
    @State private var showTabBar = true

    @StateObject private var deepLinkStore = DeepLinkStore.shared

    /// Ngăn xếp của tab Home sống ở ĐÂY chứ không phải trong `HomeView`: view đó bị huỷ
    /// mỗi khi sang tab Cá nhân (dùng `switch`, không phải `TabView`), nên deep link tới
    /// lúc đó sẽ không có chỗ nào để đẩy màn vào.
    @State private var homePath: [HomeRoute] = []
    @State private var payLinkError: String?

    private var payLinkErrorBinding: Binding<Bool> {
        Binding(get: { payLinkError != nil }, set: { if !$0 { payLinkError = nil } })
    }

    // Mirror hằng số navbar trong MainScreen.kt.
    private static let barHeight: CGFloat = 66
    private static let pillRadius: CGFloat = 32
    private static let pillMaxWidth: CGFloat = 300
    private static let qrSize: CGFloat = 62
    /// Chỉ nhô ~1/3 nút lên khỏi mép card, phần còn lại chìm trong card.
    private static let qrOverhang: CGFloat = 62 / 3
    private static let barBottomPadding: CGFloat = 12

    /// Tổng chiều cao thanh tab nổi tính từ đáy vùng an toàn — dùng cho các lớp nổi trong
    /// tab (toast, banner) tự chừa chỗ. Phơi ra `internal` vì `barHeight`/`qrOverhang` là
    /// `private`; nếu để mỗi màn tự cộng tay thì sửa chiều cao ở đây là lệch hết bên kia.
    static let floatingBarTotalHeight: CGFloat = barHeight + qrOverhang + barBottomPadding

    private static let activeTint = Color(hex: 0x00A85E)

    private var pillShape: DomeTopShape {
        DomeTopShape(
            corner: Self.pillRadius,
            flatTopY: Self.qrOverhang,
            bumpHalfWidth: Self.qrSize / 2 + 10,
            bumpPeakY: Self.qrOverhang * 0.38
        )
    }

    /// Một trang của `TabView`: nội dung + thanh tab nổi đè lên đáy.
    ///
    /// `showTabBar` do màn con phát lên qua preference, nên phải đọc ở NGOÀI closure nội
    /// dung (đọc bên trong thì preference chưa kịp truyền lên lúc dựng).
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showTabBar {
                floatingTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    var body: some View {
        Group {
            // `TabView` kiểu page thay `switch`: cho vuốt ngang qua lại giữa 2 tab.
            //
            // Không dùng `DragGesture` tự viết: Home có 2 `ScrollView(.horizontal)` (hàng
            // danh bạ nhanh, hàng gợi ý) và cả hai tab đều bọc `NavigationStack` có cử chỉ
            // back cạnh màn. Gesture tự viết sẽ tranh chấp cả hai — vuốt trên hàng danh bạ
            // thành đổi tab. `TabView` nhường đúng cử chỉ cho scroll view con.
            TabView(selection: $selectedTab) {
                // Thanh tab nằm TRONG từng trang (không phải trong ZStack ngoài `TabView`)
                // để nó trôi ngang cùng nội dung khi vuốt, thay vì đứng yên một chỗ.
                //
                // Đổi lại là mỗi trang giữ một BẢN thanh tab riêng — chấp nhận được vì nó
                // dựng từ cùng `selectedTab` nên hai bản luôn hiện cùng trạng thái.
                //
                // HomeView tự sở hữu NavigationStack riêng (push History/Contacts).
                page { HomeView(path: $homePath, isActiveTab: selectedTab == .home) }
                    .tag(Tab.home)

                // SettingsView tự sở hữu NavigationStack riêng (cần push nhiều route con:
                // Security -> ChangePassword/Devices...).
                page { SettingsView(isActiveTab: selectedTab == .settings) }
                    .tag(Tab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Vuốt quá trang đầu/cuối không nảy ra dải xám ở đáy. Mở CẢ `.top`: `TabView`
            // clip từng trang theo bounds của nó, chỉ mở đáy thì nền của Home/Cá nhân bị
            // chặn đúng mép trên safe area — hở dải trắng ở status bar (các màn ngoài
            // TabView như Login không dính vì không bị clip như vậy).
            .ignoresSafeArea(.container, edges: [.top, .bottom])
        }
        // Mở app hàng ngày -> vào thẳng màn quét QR. CHỈ mở khi không còn deep link nào
        // chờ, nếu không sẽ đè lên link nhận tiền mà người dùng vừa bấm.
        // `initial: true` vì cờ có thể được bật TRƯỚC khi view này xuất hiện (bootstrap
        // chạy ở Splash) — thiếu nó thì onChange không bao giờ khớp và QR không mở.
        .onChangeCompat(of: deepLinkStore.pendingDefaultQr, initial: true) { _, pending in
            guard pending, !deepLinkStore.hasPendingDeepLink else { return }
            deepLinkStore.consumeDefaultQr()
            showQrScan = true
        }
        // Push "xin tiền" -> mở thẳng màn Cuộc thoại. Quan sát ở đây (gốc, luôn sống)
        // thay vì trong HomeView, để bấm push lúc đang ở tab Cá nhân vẫn mở được.
        .onChangeCompat(of: deepLinkStore.pendingConversationBkUsername, initial: true) { _, value in
            guard let bkUsername = value else { return }
            _ = deepLinkStore.consumeConversation()
            openOnHome(.conversation(otherName: "", otherBkUsername: bkUsername))
        }
        .onChangeCompat(of: deepLinkStore.pendingPayToken, initial: true) { _, value in
            guard let token = value else { return }
            _ = deepLinkStore.consumePayToken()
            Task { await resolvePayLink(token: token) }
        }
        // Home Screen Quick Action (long-press icon) "Chuyển tiền tới ví" / "Chuyển khoản
        // ngân hàng" — mirror Shortcuts.ACTION_WALLET_TRANSFER/nhánh ngân hàng bên Android.
        // Cả 2 draft đều nil vì đây là mở màn NHẬP TAY, không phải "Chuyển cho <tên>" có sẵn
        // người nhận (đó là chỗ dành cho shortcut động theo danh bạ, không làm ở đây).
        .onChangeCompat(of: deepLinkStore.pendingWalletTransferShortcut, initial: true) { _, pending in
            guard pending else { return }
            _ = deepLinkStore.consumeWalletTransferShortcut()
            openOnHome(.walletTransfer(draft: nil))
        }
        .onChangeCompat(of: deepLinkStore.pendingBankTransferShortcut, initial: true) { _, pending in
            guard pending else { return }
            _ = deepLinkStore.consumeBankTransferShortcut()
            openOnHome(.bankTransfer(draft: nil))
        }
        // Siri "chuyển tiền tới ví" tầng 2 (limitPin < amount ≤ limitFace) — draft đã điền sẵn
        // người nhận/số tiền từ QuickTransferIntent, vào thẳng màn xác nhận số tiền
        // (khác 2 nhánh Quick Action ở trên: draft KHÔNG nil).
        .onChangeCompat(of: deepLinkStore.pendingQuickTransferDraft, initial: true) { _, draft in
            guard let draft else { return }
            _ = deepLinkStore.consumeQuickTransfer()
            openOnHome(.walletTransferAmount(draft))
        }
        .alert(
            "Không mở được link nhận tiền", isPresented: payLinkErrorBinding,
            actions: { Button("Đóng", role: .cancel) {} },
            message: { Text(payLinkError ?? "") }
        )
        .onPreferenceChange(TabBarVisibilityKey.self) { visible in
            showTabBar = visible
        }
        .animation(.easeInOut(duration: 0.2), value: showTabBar)
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showQrScan) {
            QrScanNavigationView(
                // Đóng màn quét thì về Trang chủ, kể cả khi mở nó từ tab Cá nhân: nút QR
                // nằm giữa thanh tab nên người dùng không coi nó thuộc tab nào, đóng ra mà
                // rơi lại vào Cá nhân thì khó hiểu. `homePath` dọn luôn để ra đúng màn gốc.
                onDismiss: {
                    showQrScan = false
                    selectedTab = .home
                    homePath.removeAll()
                },
                // "Cấp cứu" = xin tiền, chỉ chạy được giữa hai ví nội bộ nên khoá danh bạ ví.
                onEmergency: { openOnHome(.contacts(filter: .wallet)) }
            )
        }
    }

    // MARK: - Deep link

    /// Đẩy màn vào ngăn xếp Home. Vẫn chuyển tab trước dù `TabView` giữ `HomeView` sống ở
    /// mọi lúc: không chuyển thì màn được đẩy vào đúng ngăn xếp nhưng người dùng đang xem
    /// tab Cá nhân nên không thấy gì.
    /// Đóng luôn màn quét QR nếu đang mở, tránh nó che mất màn vừa đẩy.
    private func openOnHome(_ route: HomeRoute) {
        showQrScan = false
        selectedTab = .home
        homePath.append(route)
    }

    /// App tự điền sẵn vào màn chuyển tiền sau khi resolve — mirror MainActivity.kt:
    /// KHÔNG có màn "xác nhận thanh toán qua link" riêng.
    private func resolvePayLink(token: String) async {
        do {
            let info = try await PayLinkService.resolve(reqToken: token)
            switch info.payKind {
            case .bank:
                guard let accNo = info.accNo, let bankNo = info.bankNo else {
                    payLinkError = "Link nhận tiền không hợp lệ"
                    return
                }
                let bankName = BankCache.shared.bank(bin: bankNo)?.shortName
                    ?? info.bankShortName ?? "Ngân hàng"
                openOnHome(.bankTransfer(draft: BankTransferDraft(
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
                openOnHome(.walletTransferAmount(WalletTransferDraft(
                    username: benUsername,
                    holderName: info.accName ?? benUsername,
                    payLinkToken: token,
                    // Hai draft khai kiểu khác nhau: `BankTransferDraft.prefillAmount` là
                    // `Int?` còn `WalletTransferDraft.prefillAmount` là `Int64?`, nên nhánh
                    // ngân hàng ngay trên truyền thẳng được mà nhánh ví thì phải đổi kiểu.
                    prefillAmount: info.amountValue.map(Int64.init)
                )))
            }
        } catch let error as APIError {
            payLinkError = error.message
        } catch {
            payLinkError = "Không mở được link nhận tiền"
        }
    }

    private var floatingTabBar: some View {
        ZStack(alignment: .top) {
            pill
            qrFab
        }
        .frame(height: Self.barHeight + Self.qrOverhang)
        .padding(.horizontal, 16)
        .padding(.bottom, Self.barBottomPadding)
    }

    private var pill: some View {
        // Nội dung ghim ở dải barHeight dưới cùng — đúng vùng phẳng của DomeTopShape,
        // nên không bị lệch khi card cao thêm qrOverhang cho gò nhô lên.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                // Tab Trang chủ dùng logo app đơn sắc (mirror ic_nav_logo bên Android),
                // không dùng icon nhà. Logo 24pt cho cân với icon hệ thống 22pt.
                navTab(tab: .home, label: "Trang chủ") { tint in
                    NavLogoGlyph(tint: tint)
                        .frame(width: 24, height: 24)
                }
                qrSlotLabel
                navTab(tab: .settings, label: "Cá nhân") { tint in
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: Self.barHeight)
        }
        .frame(maxWidth: Self.pillMaxWidth)
        .frame(height: Self.barHeight + Self.qrOverhang)
        .background(Color.white, in: pillShape)
        .overlay {
            pillShape.stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            // Inner shadow rất nhạt ở MÉP TRÊN, clip theo contour pill (kể cả gò QR).
            LinearGradient(
                colors: [Color.black.opacity(0.07), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(pillShape)
            .allowsHitTesting(false)
        }
        .shadow(color: Color(hex: 0x101613).opacity(0.32), radius: 18, x: 0, y: 8)
    }

    /// Khe giữa card cho nút QR — chỉ có nhãn ghim đáy, thẳng dưới nút.
    private var qrSlotLabel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("Quét QR")
                .font(AppFont.beVietnamPro(11, .medium))
                .foregroundStyle(AppColor.payInk)
            Spacer().frame(height: 11)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navTab<Icon: View>(
        tab: Tab,
        label: String,
        @ViewBuilder icon: (Color) -> Icon
    ) -> some View {
        let isActive = selectedTab == tab
        let tint = isActive ? Self.activeTint : AppColor.payInk
        return Button {
            // `withAnimation` để bấm nút cũng trượt ngang như khi vuốt — gán thẳng thì
            // trang nhảy tức thì, lệch hẳn cảm giác so với cử chỉ vuốt.
            withAnimation(.easeInOut(duration: 0.25)) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                icon(tint)
                    .scaleEffect(isActive ? 1.10 : 1)
                Text(label)
                    .font(AppFont.beVietnamPro(10, isActive ? .semibold : .regular))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: isActive)
    }

    /// Nút QR: circle sạch nhô lên trên mép card — vành trắng mảnh tách khỏi card,
    /// bên trong là gradient thương hiệu.
    private var qrFab: some View {
        Button {
            showQrScan = true
        } label: {
            Circle()
                .fill(Color.white)
                .frame(width: Self.qrSize, height: Self.qrSize)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x2ECB6E), Color(hex: 0x00A24A)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(3)
                }
                .overlay {
                    AnimatedQrScanIcon()
                        .frame(width: 28, height: 28)
                }
        }
        .buttonStyle(.plain)
        .shadow(color: Color(hex: 0x00A24A).opacity(0.2), radius: 6, x: 0, y: 3)
        .accessibilityLabel("Quét QR")
    }
}

#Preview {
    MainTabView()
}
