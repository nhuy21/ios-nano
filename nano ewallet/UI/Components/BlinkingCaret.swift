//
//  BlinkingCaret.swift
//  nano ewallet
//
//  Con trỏ nhấp nháy tự vẽ cho các ô nhập dùng BÀN PHÍM SỐ TỰ VẼ (`NumericKeypad`): ô số
//  tiền, ô số tài khoản, ô số ví. Những ô đó không phải `TextField` hệ thống nên không có
//  con trỏ thật, thiếu nó thì người dùng không biết ô nào đang nhận số.
//

import SwiftUI
import Combine

struct BlinkingCaret: View {
    let color: Color
    var height: CGFloat = 20

    @State private var visible = true
    /// Timer chạy độc lập với vòng đời view — KHÔNG dùng `withAnimation(.repeatForever)` vì
    /// nó bị huỷ mỗi lần view render lại lúc gõ số, con trỏ sẽ đứng im.
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 2, height: height)
            .opacity(visible ? 1 : 0)
            .onReceive(timer) { _ in visible.toggle() }
    }
}
