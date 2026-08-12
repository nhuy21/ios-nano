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
