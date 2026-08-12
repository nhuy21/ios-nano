//
//  SettingsView.swift
//  nano ewallet
//
//  Mirror SettingsScreen.kt. Palette riêng của màn này (không hoàn toàn dùng
//  AppColor chuẩn) — giữ đúng giá trị hex khảo sát được, KỆ tên biến gốc gây
//  nhầm ("AccentOrange"/"OrangePillBg" đều là hex xanh lá, không phải cam).
//
//  Toggle "Thông báo" gọi PushRegistrar.syncCurrentToken()/unregister() thật,
//  không hardcode. Đăng xuất/hỗ trợ đều có dialog xác nhận như bản gốc.
//

import SwiftUI
import Combine
import UIKit

private enum SettingsColor {
    static let screenBg = Color(hex: 0xF7F8FA)
    static let accent = Color(hex: 0x00A85E)
    static let greenVerify = Color(hex: 0x22A45D)
    static let greenPillBg = Color(hex: 0xE8F7EF)
    static let orangePillBg = Color(hex: 0xE6F7EE)
    static let redLogout = Color(hex: 0xE5484D)
}

/// Kích thước dùng chung cho các hàng trong màn Cá nhân. `internal` (không `private`) vì
/// `BiometricSettingsSection` nằm ở file khác nhưng hàng của nó xếp cùng danh sách.
enum SettingsRowMetrics {
    /// Mọi hàng cao BẰNG NHAU, lấy mốc là hàng "Ngân hàng liên kết" (chữ 14pt + lề dọc 24
    /// mỗi bên).
    ///
    /// Phải ghim cứng chứ không để `padding` tự quyết: hàng có công tắc chứa `Toggle` cao
    /// ~31pt, còn hàng thường chỉ có chữ + chevron — cùng một padding vẫn cho ra hai chiều
    /// cao khác nhau.
    static let height: CGFloat = 68

    /// Cỡ chữ tiêu đề của hàng — dùng chung để 3 loại hàng không lệch nhau.
    static let titleFontSize: CGFloat = 14
}

private let supportPhone = "0986995079"
private let supportEmail = "nhiep9145@gmail.com"

@MainActor
struct SettingsView: View {
    /// Tab Cá nhân có đang được chọn không — xem chú thích ở `.showsTabBar` bên dưới.
    var isActiveTab: Bool = true

    private static let rowHeight = SettingsRowMetrics.height

    @StateObject private var appState = AppState.shared
    @StateObject private var authStore = AuthStore.shared

    @State private var comingSoonFeature: String?
    @State private var isLoggingOut = false
    @State private var showLogoutConfirm = false
    @State private var showSupportDialog = false

    @State private var pushEnabled = NotificationPrefs.isEnabled
    @State private var speakOnReceiveEnabled = NotificationPrefs.speakOnReceiveEnabled
    @State private var showPushDeniedAlert = false
    @State private var path: [SettingsRoute] = []

    private var showingComingSoon: Binding<Bool> {
        Binding(get: { comingSoonFeature != nil }, set: { if !$0 { comingSoonFeature = nil } })
    }

    var body: some View {
        NavigationStack(path: $path) {
            // `settingsContent` KHÔNG bù: nó tự `ignoresSafeArea(edges: .top)` rồi tự cộng
            // `topSafeAreaInset` vào chiều cao banner (xem `profileHeader`) — bù thêm ở đây là
            // cộng hai lần. Các màn con thì không tự lo nên phải bù, nếu không header của
            // chúng đè lên đồng hồ trên iOS 16→18.x.
            settingsContent
                .hidesSystemNavigationBar()
                .navigationDestination(for: SettingsRoute.self) { route in
                    destination(for: route)
                        .fillsMissingTopSafeArea()
                        .hidesSystemNavigationBar()
                }
        }
        // Chỉ tab ĐANG CHỌN được quyết định thanh tab. `MainTabView` dùng `TabView` nên cả
        // hai màn cùng sống và cùng phát preference; `reduce` gộp bằng `&&` nên nếu tab kia
        // cũng phát thì màn con của nó sẽ ẩn luôn thanh tab của tab đang xem.
        .showsTabBar(isActiveTab ? path.isEmpty : true)
        // Rời tab -> pop hết về màn gốc. `TabView` giữ view sống nên `path` vẫn còn nguyên;
        // không dọn thì vuốt từ màn con của tab kia sang đây sẽ rơi vào ĐÚNG màn con đang
        // treo dở, chứ không phải màn Cá nhân. Vuốt qua lại luôn là gốc <-> gốc.
        .onChangeNewCompat(of: isActiveTab) { active in
            if !active { path.removeAll() }
        }
    }

    /// Banner + card + avatar cuộn CÙNG nội dung, không có tiêu đề rời cố
    /// định — khác bản cũ (tiêu đề "Cá nhân" đứng yên ngoài ScrollView).
    private var settingsContent: some View {
        settingsScrollContent
        .screenBackground(SettingsColor.screenBg)
        // Cho NỘI DUNG (không chỉ nền) tràn lên status bar, để banner chạm tới đỉnh màn.
        // `screenBackground` chỉ mở safe area cho lớp nền phía sau, còn `.frame` của nó vẫn
        // giữ nội dung trong vùng an toàn — nên đặt `.ignoresSafeArea` bên trong ScrollView
        // là vô ích, phải đặt ở NGOÀI, sau `screenBackground`. Banner tự cộng bù chiều cao
        // status bar (xem `profileHeader`) nên chữ và avatar không bị đôn lên dưới đồng hồ.
        .ignoresSafeArea(edges: .top)
        .comingSoonSheet(isPresented: showingComingSoon, feature: comingSoonFeature ?? "Tính năng")
        .alert("Đăng xuất", isPresented: $showLogoutConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Đăng xuất", role: .destructive) { logout() }
        } message: {
            Text("Bạn có chắc muốn đăng xuất?")
        }
        .sheet(isPresented: $showSupportDialog) {
            SupportSheet(onDismiss: { showSupportDialog = false })
                .presentationDetents([.height(320)])
        }
        .alert("Thông báo đang bị chặn", isPresented: $showPushDeniedAlert) {
            Button("Để sau", role: .cancel) {}
            Button("Mở Cài đặt") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Bạn đã tắt quyền thông báo cho ứng dụng ở Cài đặt iOS. Hãy bật lại để nhận thông báo biến động số dư.")
        }
    }

    private var settingsScrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader

                Spacer().frame(height: 24)

                menuSection(title: "Tài khoản") {
                    navMenuRow(title: "Thông tin cá nhân", systemImage: "person.fill", route: .personalInfo)
                    divider
                    navMenuRow(title: "Ngân hàng liên kết", systemImage: "creditcard.fill", route: .linkedBanks)
                    divider
                    navMenuRow(title: "Bảo mật & Mật khẩu", systemImage: "lock.fill", route: .security)
                    divider
                    navMenuRow(title: "Ngưỡng xác thực PIN", systemImage: "slider.horizontal.3", route: .pinLimit)
                }

                Spacer().frame(height: 18)

                menuSection(title: "Cài đặt") {
                    toggleRow(
                        title: "Thông báo",
                        systemImage: "bell.fill",
                        isOn: $pushEnabled
                    ) { enabled in
                        guard enabled else {
                            NotificationPrefs.isEnabled = false
                            Task { await PushRegistrar.shared.unregister() }
                            return
                        }
                        Task {
                            // `enablePush` tự set NotificationPrefs khi thành công.
                            if await PushRegistrar.shared.enablePush() == .deniedInSystemSettings {
                                // Trả toggle về TẮT — để nó xanh là nói dối, iOS đang
                                // chặn hiển thị nên sẽ không có thông báo nào tới.
                                pushEnabled = false
                                NotificationPrefs.isEnabled = false
                                showPushDeniedAlert = true
                            }
                        }
                    }
                    divider
                    toggleRow(
                        title: "Loa báo nhận tiền",
                        systemImage: "speaker.wave.2.fill",
                        isOn: $speakOnReceiveEnabled
                    ) { enabled in
                        NotificationPrefs.speakOnReceiveEnabled = enabled
                        // Đọc thử ngay khi bật — người dùng biết loa có kêu thật không,
                        // thay vì phải chờ tới lúc có tiền vào mới phát hiện hỏng.
                        if enabled { TtsAnnouncer.shared.announceEnabled() }
                    }
                    divider
                    // Hai toggle sinh trắc — chuyển từ màn Bảo mật ra đây, xếp cùng nhóm với
                    // các công tắc khác. Section tự dựng divider ở giữa hai hàng của nó nên
                    // ở đây chỉ cần một cái phía trên.
                    BiometricSettingsSection()
                }

                Spacer().frame(height: 18)

                menuSection(title: "Khác") {
                    navMenuRow(title: "Điều khoản sử dụng", systemImage: "doc.text.fill", route: .termsOfUse)
                    divider
                    menuRow(title: "Hỗ trợ", systemImage: "questionmark.circle.fill") {
                        showSupportDialog = true
                    }
                }

                Spacer().frame(height: 24)

                logoutButton
                    .padding(.horizontal, 20)

                Spacer().frame(height: 16)

                Text("Phiên bản 1.0.0")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(height: 120)
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
    }

    private func popBack() {
        if !path.isEmpty { path.removeLast() }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .personalInfo:
            PersonalInfoView(onBack: popBack)
        case .security:
            SecurityView(
                onBack: popBack,
                onChangePassword: { path.append(.changePassword) },
                onDevicesClick: { path.append(.devices) }
            )
        case .changePassword:
            ChangePasswordView(onBack: popBack)
        case .pinLimit:
            PinLimitView(onBack: popBack)
        case .devices:
            DevicesView(onBack: popBack)
        case .linkedBanks:
            LinkedBanksView(onBack: popBack)
        case .termsOfUse:
            TermsOfUseView(onBack: popBack)
        }
    }

    // MARK: - Profile header (banner + card + avatar)

    /// Kích thước dùng chung cho phần banner/card/avatar — mirror hằng số bên
    /// `SettingsScreen.kt` (BANNER_H/CARD_RADIUS/CARD_OVERLAP/AVATAR_SIZE).
    private enum ProfileHeaderMetrics {
        static let bannerHeight: CGFloat = 170
        static let cardRadius: CGFloat = 34
        static let cardOverlap: CGFloat = 34
        static let avatarSize: CGFloat = 88
        static let avatarRing: CGFloat = 4
    }

    /// Banner tràn lên status bar + card trắng bo góc trên đè lên banner + avatar tròn đè
    /// đúng đường nối banner/card. Avatar phải là SIBLING của card (không phải con) vì card
    /// có `.clipShape` sẽ cắt mất nửa trên avatar — mirror đúng cảnh báo trong
    /// `SettingsScreen.kt` (Box "avatar phải SIBLING, không phải con của ô trắng").
    private var profileHeader: some View {
        // Chiều cao status bar — `ScrollView` đã bỏ qua safe area trên nên banner phải TỰ
        // cộng phần này vào, nếu không avatar và tên sẽ bị đôn lên nằm ngay dưới đồng hồ.
        // Đọc từ window thật thay vì hằng số cứng: tai thỏ, Dynamic Island và máy không tai
        // mỗi loại một chiều cao khác nhau.
        let topInset = UIApplication.shared.topSafeAreaInset
        let bannerHeight = ProfileHeaderMetrics.bannerHeight + topInset

        return ZStack(alignment: .top) {
            // `Color.clear` là view quyết định kích thước (tự co theo khung chứa, KHÔNG có
            // kích thước riêng); ảnh chỉ VẼ ĐÈ qua `.overlay` + `.clipped()` nên không tham
            // gia tính layout. Để `Image` làm con trực tiếp của ZStack thì ảnh gốc 1600px
            // với `.aspectRatio(.fill)` sẽ kéo giãn ZStack, đẩy cả màn tràn ra 2 bên (chữ
            // "Tài khoản"/"Cài đặt" và icon/toggle hai mép đều bị cắt).
            Color.clear
                .frame(height: bannerHeight)
                .overlay {
                    Image("banner_home")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipped()

            VStack(spacing: 0) {
                nameSection
                    .padding(.top, ProfileHeaderMetrics.avatarSize / 2 + 14)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(
                .rect(
                    topLeadingRadius: ProfileHeaderMetrics.cardRadius,
                    topTrailingRadius: ProfileHeaderMetrics.cardRadius
                )
            )
            .padding(.top, bannerHeight - ProfileHeaderMetrics.cardOverlap)

            avatar
                .padding(
                    .top,
                    bannerHeight - ProfileHeaderMetrics.cardOverlap
                        - ProfileHeaderMetrics.avatarSize / 2
                )
                .frame(maxWidth: .infinity)
        }
    }

    private var avatar: some View {
        Circle()
            .fill(Color.white)
            .frame(
                width: ProfileHeaderMetrics.avatarSize + ProfileHeaderMetrics.avatarRing * 2,
                height: ProfileHeaderMetrics.avatarSize + ProfileHeaderMetrics.avatarRing * 2
            )
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x2ECB6E), Color(hex: 0x00A24A)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: ProfileHeaderMetrics.avatarSize, height: ProfileHeaderMetrics.avatarSize)
                    .overlay {
                        Text(initials)
                            .font(AppFont.beVietnamPro(28, .heavy))
                            .foregroundStyle(.white)
                    }
            }
            .shadow(color: SettingsColor.accent.opacity(0.25), radius: 10, x: 0, y: 4)
    }

    private var nameSection: some View {
        VStack(spacing: 8) {
            Text(displayName)
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)

            // Số điện thoại chuyển hẳn sang màn Thông tin cá nhân: đây là màn ai mở máy cũng
            // liếc thấy, không cần phơi số ngay đầu.
            verificationBadge
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var isVerified: Bool {
        UserStatus(raw: authStore.lastKnownStatus) == .active
    }

    private var verificationBadge: some View {
        Button {
            if !isVerified { comingSoonFeature = "Xác thực tài khoản" }
        } label: {
            Text(isVerified ? "Đã xác thực" : "Xác thực ngay")
                .font(AppFont.beVietnamPro(12, .semibold))
                .foregroundStyle(isVerified ? SettingsColor.greenVerify : SettingsColor.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isVerified ? SettingsColor.greenPillBg : SettingsColor.orangePillBg)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isVerified)
    }

    // MARK: - Menu section

    @ViewBuilder
    private func menuSection<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.payMuted)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)
        }
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColor.line)
            .frame(height: 1)
            .padding(.leading, 56)
    }

    /// Mục menu điều hướng sang 1 màn con qua `path` — dùng cho các mục đã có UI thật
    /// (khác `menuRow` dùng cho ComingSoonSheet hoặc action tuỳ biến khác).
    private func navMenuRow(title: String, systemImage: String, route: SettingsRoute) -> some View {
        menuRow(title: title, systemImage: systemImage) {
            path.append(route)
        }
    }

    private func menuRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                rowIcon(systemImage)
                Text(title)
                    .font(AppFont.beVietnamPro(SettingsRowMetrics.titleFontSize))
                    .foregroundStyle(AppColor.payInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.horizontal, 16)
            // Ghim chiều cao thay vì để padding tự quyết: mọi hàng trong màn phải cao BẰNG
            // NHAU, mà `toggleRow` có icon 40pt còn hàng này 28pt nên cùng một padding vẫn
            // ra hai chiều cao khác nhau. Xem `Self.rowHeight`.
            .frame(height: Self.rowHeight)
            // BẮT BUỘC: `Button` + `.buttonStyle(PressableButtonStyle())` chỉ nhận chạm trên vùng VẼ THẬT
            // (chữ + icon). `Spacer()` ở giữa và phần `padding` là trong suốt nên bấm vào
            // không ăn — người dùng phải nhắm đúng chữ hoặc mũi tên mới mở được thẻ.
            // `contentShape` khai cả hàng là vùng bấm.
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func toggleRow(
        title: String, systemImage: String, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            toggleRowIcon(systemImage)
            Text(title)
                .font(AppFont.beVietnamPro(SettingsRowMetrics.titleFontSize))
                .foregroundStyle(AppColor.payInk)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(SettingsColor.accent)
                .onChangeNewCompat(of: isOn.wrappedValue) { newValue in onChange(newValue) }
        }
        // Lề ngang 16 cho khớp `menuRow` (trước là 8, nên icon lệch hẳn so với hàng trên).
        .padding(.horizontal, 16)
        .frame(height: Self.rowHeight)
    }

    /// Icon của hàng có công tắc — giữ cỡ 24pt và màu đen (`PayInk`) như `SettingRow` bên
    /// Android, nhưng khung rộng 28 BẰNG `rowIcon`: khung 40 cũ đẩy chữ lệch hẳn một cột so
    /// với các hàng ở khối trên, thấy rõ ngay khi mọi hàng đã cao bằng nhau.
    private func toggleRowIcon(_ systemImage: String) -> some View {
        rowIcon(systemImage)
    }

    /// Dùng chung cho MỌI hàng trong màn này — icon 24pt màu mực. Trước đây khối "Tài khoản"
    /// để 16pt màu xanh còn khối "Cài đặt" 24pt màu mực, nên hai khối xếp ngay cạnh nhau mà
    /// icon lệch cỡ và lệch màu.
    private func rowIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 24))
            .foregroundStyle(AppColor.payInk)
            .frame(width: 28)
    }

    // MARK: - Đăng xuất

    private var logoutButton: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            HStack(spacing: 8) {
                if isLoggingOut {
                    ProgressView().tint(SettingsColor.redLogout)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16))
                        .foregroundStyle(SettingsColor.redLogout)
                    Text("Đăng xuất")
                        .font(AppFont.beVietnamPro(15, .semibold))
                        .foregroundStyle(SettingsColor.redLogout)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoggingOut)
    }

    private func logout() {
        isLoggingOut = true
        Task {
            await appState.logout()
            isLoggingOut = false
        }
    }

    // MARK: - Derived

    private var displayName: String {
        authStore.userFullName ?? "Người dùng Nano"
    }

    private var initials: String { displayName.nameInitials }
}

/// Dialog "Hỗ trợ khách hàng" — mirror dialog trong SettingsScreen.kt.
private struct SupportSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("Hỗ trợ khách hàng")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)

            Text("Có thắc mắc hoặc cần hỗ trợ? Liên hệ với chúng tôi qua:")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                supportRow(icon: "phone.fill", label: "Số điện thoại", value: supportPhone) {
                    if let url = URL(string: "tel://\(supportPhone)") {
                        UIApplication.shared.open(url)
                    }
                }
                supportRow(icon: "envelope.fill", label: "Email", value: supportEmail) {
                    if let url = URL(string: "mailto:\(supportEmail)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .padding(.horizontal, 24)

            // Kích thước/nền phải nằm TRONG label, kèm contentShape: để ở ngoài
            // Button thì vùng bấm chỉ là mấy chữ "Đóng", nền xanh chỉ là trang trí.
            Button {
                onDismiss()
            } label: {
                Text("Đóng")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(SettingsColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        // Sheet không set nền sẽ lấy nền hệ thống — dark mode là ĐEN, mà chữ trong đây đều
        // là màu tối ghim cứng (`payInk`/`payMuted`) nên đen trên đen, không đọc được.
        //
        // Giãn hết khung TRƯỚC khi tô nền: `VStack` chỉ cao bằng nội dung, sheet thường cao
        // hơn nên tô theo `VStack` sẽ hở dải dưới lộ lại nền đen. `alignment: .top` giữ nội
        // dung ở trên, không bị dồn ra giữa khi giãn.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColor.bgSoft)
        .presentationDragIndicator(.hidden)
    }

    private func supportRow(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(SettingsColor.orangePillBg)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15))
                            .foregroundStyle(SettingsColor.accent)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(AppFont.beVietnamPro(11))
                        .foregroundStyle(AppColor.payMuted)
                    Text(value)
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.payInk)
                }
                Spacer()
            }
            // Không có contentShape thì khoảng trống do Spacer chiếm không bấm được,
            // phải chạm đúng icon/chữ mới ăn.
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

#Preview {
    SettingsView()
}
