//
//  MainTabView.swift
//  nano ewallet
//
//  Mirror MainScreen.kt — KHÔNG dùng TabView chuẩn vì Android là 1 floating pill
//  navbar custom với FAB QR nhô lên giữa. Chỉ 2 trang thật: Home (index 0) +
//  Settings (index 4 bên Android, ở đây gọi .settings) — 3 tab còn lại
//  (Financial/QrScanTab/History) KHÔNG dùng, mirror đúng theo khảo sát.
//

import SwiftUI

struct MainTabView: View {
    enum Tab { case home, settings }

    @State private var selectedTab: Tab = .home
    @State private var showQrComingSoon = false

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

            floatingTabBar
        }
        .ignoresSafeArea(.keyboard)
        .comingSoonSheet(isPresented: $showQrComingSoon, feature: "Quét QR")
    }

    private var floatingTabBar: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                tabButton(tab: .home, systemImage: "house.fill", label: "Trang chủ")

                // Khe rỗng chừa chỗ cho FAB QR nhô lên.
                Color.clear.frame(width: 62)

                tabButton(tab: .settings, systemImage: "person.fill", label: "Cá nhân")
            }
            .padding(.horizontal, 12)
            .frame(width: 300, height: 66)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)

            qrFab
                .offset(y: -62 / 3)
        }
        .padding(.bottom, 12)
    }

    private func tabButton(tab: Tab, systemImage: String, label: String) -> some View {
        let isActive = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isActive ? AppColor.brand : AppColor.ink)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var qrFab: some View {
        Button {
            showQrComingSoon = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 68, height: 68)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x2ECB6E), Color(hex: 0x00A24A)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 62, height: 62)
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: AppColor.brand.opacity(0.35), radius: 10, x: 0, y: 4)
        .accessibilityLabel("Quét QR")
    }
}

#Preview {
    MainTabView()
}
