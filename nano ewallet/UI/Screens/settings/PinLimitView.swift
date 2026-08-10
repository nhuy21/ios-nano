//
//  PinLimitView.swift
//  nano ewallet
//
//  Mirror PinLimitScreen.kt — slider + preset chip, luồng OTP 2 bước để hạ ngưỡng
//  bắt buộc nhập PIN. Chỉ nhận 0..500.000đ (WalletLimits.pinLimitMax).
//

import SwiftUI
import Combine

struct PinLimitView: View {
    let onBack: () -> Void

    @StateObject private var vm = PinLimitViewModel()
    @FocusState private var otpFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Ngưỡng xác thực PIN", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    explanationBox

                    Spacer().frame(height: 16)

                    Text("Ngưỡng hiện tại")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                    Text("\(vm.currentLimit.vndFormatted)")
                        .font(AppFont.beVietnamPro(22, .bold))
                        .foregroundStyle(AppColor.payInk)

                    Spacer().frame(height: 24)

                    if !vm.otpMode {
                        selectionSection
                    } else {
                        otpSection
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
        .screenBackground(Color(hex: 0xF7F8FA))
    }

    private var explanationBox: some View {
        Text("Giao dịch từ ngưỡng này trở lên sẽ cần nhập mã PIN. Bạn có thể điều chỉnh ngưỡng (tối đa 500.000đ, thấp nhất 0đ = luôn hỏi PIN), không nâng lên cao hơn.")
            .font(AppFont.beVietnamPro(13))
            .foregroundStyle(AppColor.payInk)
            .padding(14)
            .background(AppColor.brandSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Bước 1: chọn ngưỡng

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chọn ngưỡng mới")
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.payInk)

            Spacer().frame(height: 12)

            Text(vm.selected.vndFormatted)
                .font(AppFont.beVietnamPro(26, .bold))
                .foregroundStyle(AppColor.brand)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(height: 12)

            HStack(spacing: 12) {
                stepButton(systemImage: "minus") { adjust(-PinLimitViewModel.step) }

                Slider(
                    value: Binding(
                        get: { Double(vm.selected) },
                        set: { vm.selected = clamp(Int($0)) }
                    ),
                    in: 0...Double(WalletLimits.pinLimitMax),
                    step: Double(PinLimitViewModel.step)
                )
                .tint(AppColor.brand)

                stepButton(systemImage: "plus") { adjust(PinLimitViewModel.step) }
            }

            HStack {
                Text("0đ").font(AppFont.beVietnamPro(12)).foregroundStyle(AppColor.payMuted)
                Spacer()
                Text("500.000đ").font(AppFont.beVietnamPro(12)).foregroundStyle(AppColor.payMuted)
            }

            Spacer().frame(height: 20)

            Text("Hoặc chọn nhanh")
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.payInk)

            Spacer().frame(height: 10)

            presetGrid

            if let error = vm.error {
                FieldError(message: error)
                    .padding(.top, 12)
            }

            Spacer().frame(height: 20)

            PrimaryButton(
                title: "Lưu thay đổi",
                loadingTitle: "Đang gửi...",
                isLoading: vm.isLoading,
                isEnabled: vm.canSave,
                action: { Task { await vm.sendOtp() } }
            )
        }
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.payInk)
                .frame(width: 36, height: 36)
                .background(Color.white)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(AppColor.payInputBorder, lineWidth: 1) }
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var presetGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(PinLimitViewModel.presets, id: \.self) { preset in
                let isSelected = vm.selected == preset
                Button {
                    vm.selected = preset
                } label: {
                    Text(preset.vndFormatted)
                        .font(AppFont.beVietnamPro(13, .medium))
                        .foregroundStyle(isSelected ? AppColor.brand : AppColor.payInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(isSelected ? AppColor.brandSoft : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isSelected ? AppColor.brand : AppColor.payInputBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    // MARK: - Bước 2: OTP

    private var otpSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nhập mã OTP")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)

            Spacer().frame(height: 6)

            Text("Mã xác nhận 6 số đã gửi tới Zalo của bạn. Ngưỡng mới: \(vm.selected.vndFormatted).")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)

            Spacer().frame(height: 16)

            PinDotsField(
                value: $vm.otp,
                placeholder: "Nhập mã 6 số",
                hasError: vm.error != nil,
                dotsAlignment: .center,
                submitLabel: .done
            ) {
                Task { await confirm() }
            }
            .focused($otpFocused)

            if let error = vm.error {
                FieldError(message: error)
            }

            Spacer().frame(height: 16)

            PrimaryButton(
                title: "Xác nhận",
                loadingTitle: "Đang xử lý...",
                isLoading: vm.isLoading,
                isEnabled: vm.canConfirmOtp,
                action: { Task { await confirm() } }
            )

            Spacer().frame(height: 12)

            Button {
                Task { await vm.resendOtp() }
            } label: {
                Text("Gửi lại mã")
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(AppColor.brand)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(vm.isLoading)
        }
    }

    private func confirm() async {
        if await vm.confirm() {
            onBack()
        }
    }

    private func adjust(_ delta: Int) {
        vm.selected = clamp(vm.selected + delta)
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, 0), WalletLimits.pinLimitMax)
    }
}

#Preview {
    PinLimitView(onBack: {})
}
