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
                    HomeView()
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
        .onPreferenceChange(TabBarVisibilityKey.self) { visible in
            showTabBar = visible
        }
        .animation(.easeInOut(duration: 0.2), value: showTabBar)
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showQrScan) {
            QrScanNavigationView(onDismiss: { showQrScan = false })
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
