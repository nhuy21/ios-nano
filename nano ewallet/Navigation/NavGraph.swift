//
//  NavGraph.swift
//  nano ewallet
//

import SwiftUI

/// Điều hướng gốc — tương ứng NavGraph.kt + AppNavHost trong MainActivity.kt phía Android.
/// Logic thật nằm ở RootNavigator (chọn cây Auth/Onboarding/Main theo AppState.root).
struct NavGraph: View {
    var body: some View {
        RootNavigator()
    }
}
