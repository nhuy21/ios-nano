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

    private static let activeTint = Color(hex: 0x00A85E)

    private var pillShape: DomeTopShape {
        DomeTopShape(
            corner: Self.pillRadius,
            flatTopY: Self.qrOverhang,
            bumpHalfWidth: Self.qrSize / 2 + 10,
            bumpPeakY: Self.qrOverhang * 0.38
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    // HomeView tự sở hữu NavigationStack riêng (push History/Contacts).
                    HomeView(path: $homePath)
                case .settings:
                    // SettingsView tự sở hữu NavigationStack riêng (cần push nhiều
                    // route con: Security -> ChangePassword/Devices...).
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showTabBar {
                floatingTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        }
        // Theo dõi thông báo khi app foreground (poll + làm mới badge/hộp thư).
        // KHÔNG hiện banner trong app: `willPresent` đã trả `.banner` nên iOS tự hiện
        // banner hệ thống ngay cả lúc app đang mở — thêm banner tự vẽ nữa là hiện TRÙNG
        // hai cái. Bản Android từng mắc đúng lỗi này rồi gỡ bỏ (xem MainActivity.kt).
        .notificationWatcher()
        // Mở app hàng ngày -> vào thẳng màn quét QR. CHỈ mở khi không còn deep link nào
        // chờ, nếu không sẽ đè lên link nhận tiền mà người dùng vừa bấm.
        // `initial: true` vì cờ có thể được bật TRƯỚC khi view này xuất hiện (bootstrap
        // chạy ở Splash) — thiếu nó thì onChange không bao giờ khớp và QR không mở.
        .onChange(of: deepLinkStore.pendingDefaultQr, initial: true) { _, pending in
            guard pending, !deepLinkStore.hasPendingDeepLink else { return }
            deepLinkStore.consumeDefaultQr()
            showQrScan = true
        }
        // Push "xin tiền" -> mở thẳng màn Cuộc thoại. Quan sát ở đây (gốc, luôn sống)
        // thay vì trong HomeView, để bấm push lúc đang ở tab Cá nhân vẫn mở được.
        .onChange(of: deepLinkStore.pendingConversationBkUsername, initial: true) { _, value in
            guard let bkUsername = value else { return }
            _ = deepLinkStore.consumeConversation()
            openOnHome(.conversation(otherName: "", otherBkUsername: bkUsername))
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
        .onPreferenceChange(TabBarVisibilityKey.self) { visible in
            showTabBar = visible
        }
        .animation(.easeInOut(duration: 0.2), value: showTabBar)
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showQrScan) {
            QrScanNavigationView(onDismiss: { showQrScan = false })
        }
    }

    // MARK: - Deep link

    /// Đẩy màn vào ngăn xếp Home. PHẢI chuyển tab trước: `HomeView` chỉ được dựng khi
    /// `selectedTab == .home`, đẩy route lúc đang ở tab Cá nhân thì không ai hiển thị nó.
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
                    payLinkToken: token
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
        .padding(.bottom, 12)
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
                .font(.system(size: 11, weight: .medium))
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
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                icon(tint)
                    .scaleEffect(isActive ? 1.10 : 1)
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
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
