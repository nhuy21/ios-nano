//
//  AppTextField.swift
//  nano ewallet
//

import SwiftUI

/// Ô input 1 dòng — mirror `TextField` ở LoginScreen / `RegisterTextField` bên Android.
///
/// Spec: `heightIn(min = 56.dp)`, shadow(8, r16), clip(r16), border 1.dp
/// (`Error` khi lỗi, ngược lại `PayInputBorder`); placeholder 18sp/w400/`PayPlaceholder`;
/// chữ 18sp/w500/`PayInk`.
struct AppTextField: View {

    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var hasError: Bool = false
    var textAlignment: TextAlignment = .leading
    /// Giới hạn số ký tự (Android dùng `take(maxLength)`).
    var maxLength: Int?
    /// Chỉ cho nhập chữ số (Android filter `isDigit` với keyboard Phone/NumberPassword).
    var digitsOnly: Bool = false
    var onSubmit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text, prompt: promptView)
            .font(AppFont.beVietnamPro(18, .medium))
            .foregroundStyle(AppColor.payInk)
            .multilineTextAlignment(textAlignment)
            .keyboardType(keyboardType)
            .submitLabel(submitLabel)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFocused)
            .tint(AppColor.brand)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(hasError ? AppColor.errorSoft : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(hasError ? AppColor.error : AppColor.payInputBorder, lineWidth: 1)
            }
            .inputShadow()
            .onChangeNewCompat(of: text) { newValue in
                var cleaned = digitsOnly ? newValue.filter(\.isNumber) : newValue
                if let maxLength { cleaned = String(cleaned.prefix(maxLength)) }
                if cleaned != newValue { text = cleaned }
            }
            .onSubmit(onSubmit)
    }

    private var promptView: Text {
        Text(placeholder)
            .font(AppFont.beVietnamPro(18))
            .foregroundColor(AppColor.payPlaceholder)
    }
}

/// Ô nhập số dùng bàn phím TỰ VẼ (`PlainNumericKeypad`) thay bàn phím hệ thống.
///
/// Không phải `TextField`: chỉ cần một `TextField` tồn tại và được focus là iOS bật bàn phím
/// hệ thống lên chồng với bàn phím tự vẽ. Nên ô này chỉ HIỂN THỊ — nền, viền, caret nháy đều
/// tự vẽ cho giống hệt `AppTextField`, còn ký tự do nơi gọi bơm vào qua binding.
///
/// Tiêu điểm cũng do nơi gọi giữ (`isFocused`), vì nó là thứ quyết định bàn phím hiện cho ô
/// nào — chỉ ô này biết thì màn không điều phối được nhiều ô.
struct KeypadTextField: View {
    let text: String
    let placeholder: String
    var hasError: Bool = false
    var textAlignment: TextAlignment = .leading
    /// Hiện chấm tròn thay chữ số — cho ô mật khẩu.
    var isSecure: Bool = false
    let isFocused: Bool
    let onTap: () -> Void

    /// Nhịp nháy chạy độc lập với vòng đời view, cùng 0.5s với `PinDotsField` để nhiều ô trên
    /// một màn không lệch pha. Không dùng `withAnimation(.repeatForever)` vì animation đó bị
    /// huỷ mỗi lần view render lại — gõ thêm một số là caret đứng im.
    @State private var caretVisible = true
    private let caretTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var alignment: Alignment {
        textAlignment == .center ? .center : .leading
    }

    var body: some View {
        HStack(spacing: 0) {
            if textAlignment == .center { Spacer(minLength: 0) }

            if text.isEmpty && !isFocused {
                Text(placeholder)
                    .font(AppFont.beVietnamPro(18))
                    .foregroundStyle(AppColor.payPlaceholder)
            } else {
                Text(isSecure ? String(repeating: "●", count: text.count) : text)
                    .font(AppFont.beVietnamPro(18, .medium))
                    .foregroundStyle(AppColor.payInk)
                if isFocused {
                    Rectangle()
                        .fill(AppColor.brand)
                        .frame(width: 2, height: 24)
                        .opacity(caretVisible ? 1 : 0)
                        .padding(.leading, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: alignment)
        .background(hasError ? AppColor.errorSoft : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hasError ? AppColor.error : AppColor.payInputBorder, lineWidth: 1)
        }
        .inputShadow()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onReceive(caretTimer) { _ in
            guard isFocused else {
                caretVisible = false
                return
            }
            caretVisible.toggle()
        }
        .onChangeNewCompat(of: text) { _ in
            // Vừa gõ/xoá thì caret sáng lại ngay, không phải chờ nhịp timer kế tiếp.
            if isFocused { caretVisible = true }
        }
    }
}

/// Nhãn phía trên input — 14sp/w600/`PayInk`, cách input 8.dp (Login) hoặc 13sp (Register).
struct FieldLabel: View {
    let text: String
    var size: CGFloat = 14
    /// Trường bắt buộc — thêm dấu `*` đỏ sau nhãn.
    var required: Bool = false

    var body: some View {
        label
            .font(AppFont.beVietnamPro(size, .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }

    /// Dấu `*` để RIÊNG một `Text` màu đỏ chứ không nối vào chuỗi nhãn: nối vào thì nó thừa
    /// hưởng màu chữ nhãn, mắt không nhận ra đó là dấu bắt buộc.
    /// `foregroundColor` chứ KHÔNG phải `foregroundStyle`: bản trả về `Text` (để nối hai
    /// `Text` bằng `+`) của `foregroundStyle` chỉ có từ iOS 17, mà app hỗ trợ từ iOS 16.
    @ViewBuilder
    private var label: some View {
        if required {
            Text(text).foregroundColor(AppColor.payInk)
                + Text(" *").foregroundColor(AppColor.error)
        } else {
            Text(text).foregroundColor(AppColor.payInk)
        }
    }
}

/// Dòng lỗi dưới input — 12sp/`Error`. Login/ForgotPassword canh giữa, Register canh trái.
struct FieldError: View {
    let message: String
    var alignment: TextAlignment = .center

    var body: some View {
        Text(message)
            .font(AppFont.beVietnamPro(12))
            .foregroundStyle(AppColor.error)
            .multilineTextAlignment(alignment)
            .frame(
                maxWidth: .infinity,
                alignment: alignment == .center ? .center : .leading
            )
            .padding(.top, 6)
    }
}
