//
//  MainScreen.swift
//  nano ewallet
//
//  Created by Le Tran Nhu Y on 30/7/26.
//

import SwiftUI

/// Màn hình chính (tab bar) — tương ứng MainScreen.kt phía Android (flash-wallet).
struct MainScreen: View {
    var body: some View {
        VStack {
            Image(systemName: "wallet.pass")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("NanoWallet")
        }
        .padding()
    }
}

#Preview {
    MainScreen()
}
