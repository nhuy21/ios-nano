//
//  SplashView.swift
//  nano ewallet
//
//  Mirror SplashScreen.kt — chỉ hiện logo + spinner, không có tương tác.
//  AppState.bootstrap() lo toàn bộ logic điều hướng (xem App/AppState.swift).
//

import SwiftUI

struct SplashView: View {
    @StateObject private var appState = AppState.shared

    var body: some View {
        VStack {
            Image("logo_main")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 240)
                .accessibilityLabel("Ví nano")

            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColor.brand)
                .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 48)
        .background(Color.white)
        .task {
            await appState.bootstrap()
        }
    }
}

#Preview {
    SplashView()
}
