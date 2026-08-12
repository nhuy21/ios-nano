//
//  NumericKeypad.swift
//  nano ewallet
//
//  Bàn phím số tự vẽ, thay bàn phím hệ thống để có phím hành động ("Tiếp") ngay trong bàn
//  phím. Hai bản:
//
//  - `NumericKeypad`: có phím "000" — cho các ô NHẬP TIỀN, gõ tắt hàng nghìn.
//  - `PlainNumericKeypad`: không có "000" — cho ô mà gõ tắt là sai (số tài khoản, CCCD,
//    OTP...). Hàng cuối là "," 0 "." — 0 vào giữa như bàn phím hệ thống, hai dấu hai bên
//    chỉ để lấp cho kín hàng.
//
//  Bố cục chung: 3 cột số bên trái (1..9 rồi hàng cuối) + cột phải gồm Xoá và Tiếp, mỗi nút
//  cao 2 hàng. Phím "." chỉ để giữ bố cục — VNĐ là số nguyên nên không nhập gì.
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

/// Bàn phím số KHÔNG có phím "000" — cho những ô nhập mà gõ tắt hàng nghìn là sai: số tài
/// khoản, số CCCD, mã OTP, số lượng...
///
/// Khác `NumericKeypad` đúng ở chỗ đó và ở hàng cuối: bỏ "000" thì đưa "0" vào GIỮA như bàn
/// phím hệ thống, hai bên là "," và "." — hai dấu này chỉ lấp cho kín hàng, bấm không nhập
/// gì. Để trống hẳn thì hàng cuối hở một mảng nền, nhìn như bàn phím bị thiếu phím.
///
/// Tách thành view riêng chứ không thêm cờ `showsTripleZero` vào `NumericKeypad`: hai bàn
/// phím khác nhau cả bố cục hàng cuối, nhồi vào một view thì thân view đầy nhánh `if` mà
/// mỗi nơi gọi chỉ dùng đúng một nhánh.
struct PlainNumericKeypad: View {
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

    /// "," và "." chỉ để lấp hai ô hai bên phím 0 cho kín hàng — bấm không nhập gì. Bỏ trống
    /// hẳn thì hàng cuối hở một mảng nền, nhìn như bàn phím bị thiếu phím.
    private static let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [",", "0", "."],
    ]

    /// Phím có mặt cho cân bố cục nhưng không sinh ký tự nào.
    private static let decorativeKeys: Set<String> = [",", "."]

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
            guard !Self.decorativeKeys.contains(label) else { return }
            onDigit(label)
        } label: {
            Text(label)
                .font(AppFont.beVietnamPro(24))
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
