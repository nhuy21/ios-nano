//
//  NavGraph.swift
//  nano ewallet
//

import SwiftUI

/// Điều hướng gốc — tương ứng NavGraph.kt phía Android.
struct NavGraph: View {
    var body: some View {
        NavigationStack {
            MainScreen()
        }
    }
}
