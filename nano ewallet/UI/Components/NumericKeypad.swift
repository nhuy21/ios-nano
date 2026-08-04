//
//  NumericKeypad.swift
//  nano ewallet
//
//  Bàn phím số tự vẽ, dùng chung cho các màn nhập tiền. Thay bàn phím hệ thống để có
//  thêm phím "000" và phím hành động "Tiếp" ngay trong bàn phím.
//
//  Bố cục: 3 cột số bên trái (1..9, 000, 0, .) + cột phải gồm Xoá và Tiếp, mỗi nút cao
//  2 hàng. Phím "." chỉ để giữ bố cục — VNĐ là số nguyên nên không nhập gì.
//
//  Chiều cao tổng lấy theo bàn phím số của hệ thống (~216pt) để mỗi ô phím bằng cỡ ô
//  phím hệ thống, thay vì cao như bản Android.
//

import SwiftUI

struct NumericKeypad: View {
    let onDigit: (String) -> Void
    let onBackspace: () -> Void
    let onNext: () -> Void
    var nextTitle: String = "Tiếp"
    var nextEnabled: Bool = true
    var nextActiveColor: Color = Color(hex: 0x00A85E)

    /// Bằng chiều cao bàn phím số hệ thống trên iPhone.
    private static let totalHeight: CGFloat = 216
    private static let gap: CGFloat = 6

    private enum KpColor {
        static let background = Color(hex: 0xCBD0D6)
        static let key = Color.white
        static let keyText = Color(hex: 0x141414)
        static let backspace = Color(hex: 0xA7AEB6)
        static let backspaceIcon = Color(hex: 0x33383E)
        static let nextDisabled = Color(hex: 0xE6E7EA)
        static let nextDisabledText = Color(hex: 0x9BA0A6)
    }

    private static let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["000", "0", "."],
    ]

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: Self.gap) {
                ForEach(Self.rows, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(row, id: \.self) { label in
                            digitKey(label)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: Self.gap) {
                backspaceKey
                nextKey
            }
            .frame(width: 84)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .frame(height: Self.totalHeight)
        .frame(maxWidth: .infinity)
        .background(KpColor.background)
    }

    private func digitKey(_ label: String) -> some View {
        Button {
            // VNĐ là số nguyên -> phím "." chỉ để giống bố cục, không nhập gì.
            guard label != "." else { return }
            onDigit(label)
        } label: {
            Text(label)
                .font(AppFont.beVietnamPro(label == "000" ? 20 : 24))
                .foregroundStyle(KpColor.keyText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KpColor.key)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(KeyPressStyle())
    }

    private var backspaceKey: some View {
        Button(action: onBackspace) {
            Image(systemName: "delete.left.fill")
                .font(.system(size: 22))
                .foregroundStyle(KpColor.backspaceIcon)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KpColor.backspace)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel("Xoá")
    }

    private var nextKey: some View {
        Button(action: onNext) {
            Text(nextTitle)
                .font(AppFont.beVietnamPro(17, .semibold))
                .foregroundStyle(nextEnabled ? .white : KpColor.nextDisabledText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(nextEnabled ? nextActiveColor : KpColor.nextDisabled)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!nextEnabled)
    }
}

/// Phím tối đi khi bấm — bàn phím hệ thống cũng phản hồi kiểu này.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}
