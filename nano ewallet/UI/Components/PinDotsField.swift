//
//  PinDotsField.swift
//  nano ewallet
//

import SwiftUI
import Combine

/// Ô nhập mật khẩu 6 chữ số dạng 6 dấu tròn — mirror khối password inline ở
/// LoginScreen / RegisterScreen / WelcomeBackScreen bên Android.
///
/// Cách hoạt động giống Android: 1 `TextField` ẩn (alpha 0) nhận bàn phím số, phía trên
/// vẽ 6 slot. Bấm vào vùng nào cũng focus vào field ẩn.
///
/// Spec Android: box `heightIn(min = 56.dp)`, shadow(8, r16), border 1.dp, slot 14×22.dp,
/// dot 11.dp, khoảng cách 14.dp; chữ hiện 18sp/w600.
struct PinDotsField: View {

    /// `HorizontalAlignment` của SwiftUI không conform `Equatable`, nên không so sánh
    /// `==` được — dùng enum riêng rồi tự map sang alignment lúc layout.
    enum DotsAlignment: Hashable {
        case leading
        case center
    }

    @Binding var value: String
    var placeholder: String = "Nhập mật khẩu"
    var hasError: Bool = false
    /// `.leading` cho Login/Register, `.center` cho WelcomeBack.
    var dotsAlignment: DotsAlignment = .leading
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}

    @State private var showValue = false
    @FocusState private var isFocused: Bool
    @State private var caretVisible = true

    /// Nhịp nháy chạy độc lập với vòng đời view. Không dùng
    /// `withAnimation(.repeatForever)` vì animation đó bị huỷ mỗi lần view render
    /// lại — gõ thêm 1 số là `value` đổi -> render lại -> caret đứng im.
    private let caretTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private let maxLength = 6
    private let dotSpacing: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {
            // Field ẩn nhận input. `.keyboardType(.numberPad)` + filter số ở onChange.
            TextField("", text: $value)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .submitLabel(submitLabel)
                .focused($isFocused)
                .opacity(0)
                .frame(width: 1, height: 1)
                .onChange(of: value) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(maxLength))
                    if filtered != newValue { value = filtered }
                }
                .onSubmit(onSubmit)

            if !isFocused && value.isEmpty {
                Text(placeholder)
                    .font(AppFont.beVietnamPro(18))
                    .foregroundStyle(AppColor.payPlaceholder)
                    .frame(
                        maxWidth: .infinity,
                        alignment: dotsAlignment == .center ? .center : .leading
                    )
                    .padding(.leading, dotsAlignment == .center ? 0 : 16)
            } else {
                dots
                    .frame(
                        maxWidth: .infinity,
                        alignment: dotsAlignment == .center ? .center : .leading
                    )
                    .padding(.leading, dotsAlignment == .center ? 0 : 16)
            }

            if !value.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        showValue.toggle()
                    } label: {
                        Image(systemName: showValue ? "eye.slash" : "eye")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColor.payPlaceholder)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .accessibilityLabel(showValue ? "Ẩn mật khẩu" : "Hiện mật khẩu")
                }
            }
        }
        .frame(minHeight: 56)
        .background(hasError ? AppColor.errorSoft : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hasError ? AppColor.error : AppColor.payInputBorder, lineWidth: 1)
        }
        .inputShadow()
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onReceive(caretTimer) { _ in
            guard isFocused else {
                caretVisible = false
                return
            }
            caretVisible.toggle()
        }
        .onChange(of: isFocused, initial: true) { _, focused in
            // Vừa focus: hiện caret ngay, không phải chờ tới nhịp timer kế tiếp.
            caretVisible = focused
        }
        .onChange(of: value) { _, _ in
            // Vừa gõ/xoá: caret sáng lại và nhảy sang ô mới ngay, giống caret thật.
            if isFocused { caretVisible = true }
        }
    }

    private var dots: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<maxLength, id: \.self) { index in
                let digit = digitAt(index)
                // Ô đang chờ nhập tiếp theo — chỉ 1 ô duy nhất, và chỉ khi field đang focus.
                let isActiveSlot = isFocused && index == value.count

                ZStack {
                    if showValue, let digit {
                        Text(String(digit))
                            .font(AppFont.beVietnamPro(18, .semibold))
                            .foregroundStyle(AppColor.payInk)
                    } else if digit != nil {
                        Circle()
                            .fill(AppColor.payInk)
                            .frame(width: 11, height: 11)
                    } else if isActiveSlot {
                        Rectangle()
                            .fill(AppColor.brand)
                            .frame(width: 2, height: 24)
                            .opacity(caretVisible ? 1 : 0)
                    } else {
                        Circle()
                            .fill(AppColor.payPlaceholder.opacity(0.35))
                            .frame(width: 11, height: 11)
                    }
                }
                .frame(width: 14, height: 22)
            }
        }
    }

    private func digitAt(_ index: Int) -> Character? {
        guard index < value.count else { return nil }
        return value[value.index(value.startIndex, offsetBy: index)]
    }
}
