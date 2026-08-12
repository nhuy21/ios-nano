//
//  ReceiveQrView.swift
//  nano ewallet
//
//  Mirror ReceiveQrScreen.kt — "QR của tôi" (nhận tiền). Tự build VietQR (EMVCo) từ
//  vaBankNo/vaNumber (virtual account Bảo Kim cấp riêng cho ví, KHÁC bkUsername) tại
//  client bằng VietQrBuilder — không dùng ảnh qr_path. Sinh ảnh QR bằng CoreImage
//  (CIFilter.qrCodeGenerator) thay ZXing bên Android.
//

import SwiftUI
import Combine
import CoreImage.CIFilterBuiltins
import UIKit
import Photos

@MainActor
struct ReceiveQrView: View {
    let onBack: () -> Void

    @StateObject private var wallet = WalletStore.shared

    @State private var fixedAmount: Int?
    @State private var showAmountSheet = false
    @State private var amountInput = ""
    @State private var shareItem: ShareableImage?
    @State private var toastMessage: String?

    @State private var showPayLinkSheet = false
    @State private var payLinkAmountInput = ""
    @State private var isCreatingPayLink = false
    @State private var payLinkError: String?
    @State private var shareTextItem: ShareableText?
    @State private var showQuickTopUp = false

    /// Ô số tiền trong hai dialog dùng bàn phím số TỰ VẼ (có phím "000"), nên tiêu điểm chỉ
    /// là cờ `@State` — không có `TextField` thật để mà `@FocusState`.
    @State private var isAmountKeypadOpen = false
    @State private var isPayLinkKeypadOpen = false

    private var qrContent: String? {
        guard let bin = wallet.vaBankNo, !bin.isEmpty,
              let number = wallet.vaNumber, !number.isEmpty else { return nil }
        return VietQrBuilder.build(
            bankBin: bin, accountNumber: number,
            purposeMessage: "Nap so du vi Baokim", amount: fixedAmount
        )
    }

    private var displayName: String { wallet.accName ?? "Ví Nano" }
    private var displayNo: String { wallet.bkUsername ?? "—" }

    /// Gradient thương hiệu làm nền dự phòng (mép hở khi tỉ lệ màn khác ảnh
    /// thì vẫn ra xanh thương hiệu chứ không hở nền trắng) + ảnh `background_nano` phủ toàn
    /// màn — ảnh đã có sẵn hoạ tiết nên không cần vẽ thêm lớp trang trí nào khác.
    /// `.ignoresSafeArea()` đặt NGAY TRÊN layer này (không phải ở ZStack cha) — theo đúng
    /// pattern chuẩn: nền/ảnh trang trí ignore safe area, nội dung tương tác (header/nút)
    /// vẫn tôn trọng safe area như bình thường.
    private var brandBackground: some View {
        // Gradient là view GỐC quyết định kích thước (tự co giãn theo khung chứa, không có
        // kích thước riêng); ảnh đưa vào `.overlay` + `.clipped()` nên nó chỉ VẼ ĐÈ lên,
        // KHÔNG tham gia tính layout. Để ảnh là con trực tiếp của ZStack thì ảnh gốc
        // 1600px với `.scaledToFill()` sẽ kéo giãn ZStack, đẩy cả màn hình tràn ra 2 bên.
        LinearGradient(
            colors: [Color(hex: 0x00A85E), Color(hex: 0x007E47)],
            startPoint: .top, endPoint: .bottom
        )
        .overlay {
            Image("background_nano")
                .resizable()
                .scaledToFill()
        }
        // KHÔNG dùng `.clipped()` ở đây: nó cắt ảnh theo bounds TẠI THỜI ĐIỂM gọi, nên đặt
        // trước `.ignoresSafeArea()` thì vùng status bar mở thêm ra chỉ còn gradient trơn
        // (mất hoạ tiết ảnh), còn đặt sau thì cắt lại đúng phần vừa mở. Không cần nó nữa —
        // `.overlay` vốn đã không cho ảnh tham gia tính layout, đó mới là thứ chống tràn.
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            // Đặt RIÊNG ở layer đáy, tự giãn hết bounds nhờ `.ignoresSafeArea()` của chính
            // nó — `VStack` nội dung bên dưới KHÔNG ignoresSafeArea nên vẫn tôn trọng safe
            // area như bình thường (header không đè lên đồng hồ/pin), trong khi nền vẫn
            // tràn hết lên status bar/home indicator.
            brandBackground

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 16) {
                        billCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
                quickTopUpPill
                actionRow
            }
        }
        // Màn tự vẽ header/nút back riêng (nút "arrow.left" ở trên) — thiếu modifier này thì
        // navigation bar hệ thống (dù ẩn UI) vẫn chừa khoảng trên, khiến `brandBackground`
        // dù đã `.ignoresSafeArea()` cũng không tràn hết lên được status bar.
        .hidesSystemNavigationBar()
        .instantOverlayCover(isPresented: $showQuickTopUp) {
            QuickTopUpSheet(
                onDismiss: { showQuickTopUp = false },
                onOpenedBankApp: {
                    DeepLinkStore.shared.markTopUpStarted(balanceBefore: wallet.balance)
                }
            )
        }
        .task { await wallet.refresh() }
        // Dialog phủ TOÀN màn (nền tối riêng) thay vì sheet 240pt — sheet thấp vẫn để lộ
        // màn QR phía sau. Cùng cách Login dựng DeviceConflictDialog/DeviceOtpDialog.
        .fullScreenCover(isPresented: $showAmountSheet) {
            amountSheet
                .transparentSheetBackground()
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.image])
        }
        .sheet(item: $shareTextItem) { item in
            ActivityShareSheet(items: [item.text])
        }
        // Cùng kiểu dialog phủ toàn màn như "Thêm số tiền".
        .fullScreenCover(isPresented: $showPayLinkSheet) {
            payLinkSheet
                .transparentSheetBackground()
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, 100)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())

            Text("QR nhận tiền")
                .font(AppFont.beVietnamPro(20, .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bill card

    /// Thứ tự theo ReceiveQrScreen.kt: logo VietQR -> khung QR có viền -> hàng logo
    /// napas 247 | Bảo Kim -> tên -> số ví -> "+ Thêm số tiền".
    private var billCard: some View {
        VStack(spacing: 0) {
            billContent

            Spacer().frame(height: 12)

            Button {
                amountInput = fixedAmount.map { $0.vndGrouped } ?? ""
                showAmountSheet = true
            } label: {
                Text(fixedAmount != nil ? "+ Đổi số tiền" : "+ Thêm số tiền")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }

    /// Phần thẻ dùng chung cho cả màn hình lẫn ảnh lưu/chia sẻ — KHÔNG gồm nút
    /// "Thêm số tiền" vì nút đó vô nghĩa trong ảnh gửi cho người khác.
    private var billContent: some View {
        VStack(spacing: 0) {
            Image("logo_vietqr")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 30)
                .accessibilityLabel("VietQR")

            Spacer().frame(height: 14)

            // Khung viền vuông bao QR. KHÔNG chèn logo vào giữa mã — che module của mã
            // tự dựng dễ làm máy quét đọc sai (ghi chú nguyên văn bên Kotlin).
            Group {
                if let qrContent, let image = Self.qrImage(for: qrContent) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    Text("Chưa có số ví")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(12)
            .frame(width: 180, height: 180)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColor.payMuted, lineWidth: 2)
            }

            Spacer().frame(height: 16)

            HStack(spacing: 8) {
                Image("logo_napas")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 16)
                    .accessibilityLabel("NAPAS 247")

                Rectangle()
                    .fill(AppColor.payMuted)
                    .frame(width: 2, height: 14)

                Image("logo_baokim_wordmark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 16)
                    .accessibilityLabel("Bảo Kim")
            }

            Spacer().frame(height: 14)

            Text(displayName)
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 2)

            Text("Số ví · \(displayNo)")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)

            if let fixedAmount {
                Spacer().frame(height: 8)
                Text("Số tiền: \(fixedAmount.vndFormatted)")
                    .font(AppFont.beVietnamPro(22, .bold))
                    .foregroundStyle(AppColor.brand)
            }
        }
    }

    /// Ảnh xuất ra khi lưu/chia sẻ — mirror `buildQrBillBitmap` bên Kotlin: card trắng
    /// đủ logo VietQR, khung QR, dải napas|Bảo Kim, tên và số ví. Trước đây xuất mã QR
    /// TRẦN nên người nhận ảnh chỉ thấy ô vuông đen trắng, không biết ví của ai.
    private var exportBill: some View {
        billContent
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .frame(width: 340)
            .background(Color.white)
    }

    /// `nil` khi chưa có số ví (chưa dựng được mã) — cùng điều kiện với `qrContent`.
    private func renderQrBill() -> UIImage? {
        guard qrContent != nil else { return nil }
        let renderer = ImageRenderer(content: exportBill)
        renderer.scale = 3
        return renderer.uiImage
    }

    // MARK: - Action row

    /// Lối tắt sang "Nạp ví nhanh" — đứng ngay trên hàng thao tác vì nó là cách nạp tiền
    /// nhanh hơn hẳn so với việc tự copy số tài khoản trên mã QR rồi dán sang app ngân hàng.
    private var quickTopUpPill: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Nạp ví nhanh")
                    .font(AppFont.beVietnamPro(13.5, .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.18), in: Capsule())
            .contentShape(Capsule())
            .pressable { showQuickTopUp = true }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton(icon: "square.and.arrow.up", title: "Chia sẻ mã QR") {
                shareQr()
            }
            actionButton(icon: "square.and.arrow.down", title: "Lưu vào thư viện") {
                saveQr()
            }
            actionButton(icon: "link", title: "Link nhận tiền") {
                payLinkAmountInput = ""
                payLinkError = nil
                showPayLinkSheet = true
            }
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(AppColor.brand)
                Text(title)
                    .font(AppFont.beVietnamPro(11, .medium))
                    .foregroundStyle(AppColor.payInk)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Amount sheet

    /// Ô số tiền hiển thị thuần cho hai dialog — KHÔNG phải `TextField`: chúng dùng bàn phím
    /// số tự vẽ, để `TextField` được focus là iOS bật bàn phím hệ thống lên đè lên.
    ///
    /// Không có chips gợi ý ở đây (khác màn rút tiền / chuyển ví): hai dialog này chỉ gắn số
    /// tiền vào QR hoặc link, không phải luồng chuyển tiền có mệnh giá quen thuộc.
    private func keypadAmountField(
        text: String,
        isFocused: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 1) {
            if text.isEmpty {
                Text("0")
                    .font(AppFont.beVietnamPro(18))
                    .foregroundStyle(AppColor.payPlaceholder)
            } else {
                Text(Int(text.amountValue).vndGrouped)
                    .font(AppFont.beVietnamPro(18, .medium))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if isFocused {
                BlinkingCaret(color: AppColor.payInk, height: 20)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
        }
        .inputShadow()
        .contentShape(Rectangle())
        .onTapGesture {
            KeypadDismissGuard.markHandled()
            onTap()
        }
    }

    // MARK: - Nhập số tiền (bàn phím tự vẽ)

    /// Chặn số 0 dẫn đầu và giới hạn 9 chữ số, giống các màn nhập tiền khác.
    private func appendDigits(_ digits: String, to text: inout String) {
        let combined = text.isEmpty && digits.allSatisfy { $0 == "0" } ? "" : text + digits
        text = String(combined.prefix(9))
    }

    private func backspaceDigit(from text: inout String) {
        guard !text.isEmpty else { return }
        text.removeLast()
    }

    private var amountSheet: some View {
        VStack(spacing: 16) {
            Text("Thêm số tiền vào mã QR")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)

            keypadAmountField(text: amountInput, isFocused: isAmountKeypadOpen) {
                isAmountKeypadOpen = true
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button {
                    fixedAmount = nil
                    showAmountSheet = false
                } label: {
                    Text("Bỏ số tiền")
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.payMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: 0xF1F3F5))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    fixedAmount = Int(amountInput.amountDigits)
                    showAmountSheet = false
                } label: {
                    Text("Xong")
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    // Bàn phím đang mở thì chạm nền chỉ cất bàn phím, chạm lần nữa mới
                    // đóng dialog — như mọi ô nhập khác.
                    if isAmountKeypadOpen { isAmountKeypadOpen = false } else { showAmountSheet = false }
                }
)
        // Bàn phím số tự vẽ, bản CÓ phím "000" vì đây là ô nhập TIỀN.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isAmountKeypadOpen {
                NumericKeypad(
                    onDigit: { appendDigits($0, to: &amountInput) },
                    onBackspace: { backspaceDigit(from: &amountInput) },
                    onNext: { isAmountKeypadOpen = false },
                    nextTitle: "Xong"
                )
            }
        }
    }


    // MARK: - Pay link sheet

    /// Mirror `AmountInputDialog(allowEmpty = true)` ở ReceiveQrScreen.kt — chỉ nhập số
    /// tiền (để trống = người gửi tự nhập), không có ô nội dung.
    private var payLinkSheet: some View {
        VStack(spacing: 16) {
            Text("Tạo link nhận tiền")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)

            Text("Nhập số tiền cần nhận (để trống nếu để người gửi tự nhập)")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            keypadAmountField(text: payLinkAmountInput, isFocused: isPayLinkKeypadOpen) {
                isPayLinkKeypadOpen = true
            }
            .padding(.horizontal, 20)

            if let payLinkError {
                FieldError(message: payLinkError, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 12) {
                Button {
                    showPayLinkSheet = false
                } label: {
                    Text("Huỷ")
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.payMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: 0xF1F3F5))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    Task { await createAndSharePayLink() }
                } label: {
                    Group {
                        if isCreatingPayLink {
                            ProgressView().tint(.white)
                        } else {
                            Text("Tạo & chia sẻ")
                                .font(AppFont.beVietnamPro(14, .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColor.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isCreatingPayLink)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    // Bàn phím đang mở thì chạm nền chỉ cất bàn phím, chạm lần nữa mới
                    // đóng dialog — như mọi ô nhập khác.
                    if isPayLinkKeypadOpen { isPayLinkKeypadOpen = false } else { showPayLinkSheet = false }
                }
)
        // Bàn phím số tự vẽ, bản CÓ phím "000" vì đây là ô nhập TIỀN.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isPayLinkKeypadOpen {
                NumericKeypad(
                    onDigit: { appendDigits($0, to: &payLinkAmountInput) },
                    onBackspace: { backspaceDigit(from: &payLinkAmountInput) },
                    onNext: { isPayLinkKeypadOpen = false },
                    nextTitle: "Xong"
                )
            }
        }
    }


    private func createAndSharePayLink() async {
        guard !isCreatingPayLink else { return }
        payLinkError = nil
        isCreatingPayLink = true
        defer { isCreatingPayLink = false }
        do {
            let result = try await PayLinkService.create(
                CreatePayLinkRequest(amount: Int(payLinkAmountInput.amountDigits), note: nil)
            )
            showPayLinkSheet = false
            shareTextItem = ShareableText(text: "Chuyển tiền cho tôi qua Nano Wallet: \(result.url)")
        } catch let error as APIError {
            payLinkError = error.message
        } catch {
            payLinkError = "Tạo link thất bại, vui lòng thử lại"
        }
    }

    // MARK: - Share / Save

    private func shareQr() {
        guard let image = renderQrBill() else {
            showToast("Chưa có số ví để tạo mã")
            return
        }
        shareItem = ShareableImage(image: image)
    }

    /// Dùng `PHPhotoLibrary` thay `UIImageWriteToSavedPhotosAlbum(_, nil, nil, nil)`:
    /// bản kia không có completion nên nuốt mọi lỗi — user từ chối quyền ảnh thì không
    /// có gì được lưu nhưng vẫn hiện "Đã lưu mã QR vào thư viện".
    private func saveQr() {
        guard let image = renderQrBill() else {
            showToast("Chưa có số ví để tạo mã")
            return
        }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                showToast("Cần quyền truy cập thư viện ảnh để lưu mã QR")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                showToast("Đã lưu mã QR vào thư viện")
            } catch {
                showToast("Lưu ảnh thất bại, vui lòng thử lại")
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toastMessage == message { toastMessage = nil }
        }
    }

    /// Sinh ảnh QR từ chuỗi EMVCo qua CoreImage — mirror ZXing `QRCodeWriter` bên Android
    /// (error correction cao nhất để giữ độ tin cậy khi hiển thị nhỏ).
    private static func qrImage(for content: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "H"
        guard let outputImage = filter.outputImage else { return nil }
        let scale = 640 / outputImage.extent.width
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return overlayVietQrMark(on: UIImage(cgImage: cgImage))
    }

    /// Vẽ logo "V" của VietQR vào chính giữa mã, trên một nền trắng bo tròn để tách khỏi
    /// các ô đen xung quanh. An toàn vì mã đã dựng ở mức sửa lỗi H (~30%).
    private static func overlayVietQrMark(on qr: UIImage) -> UIImage {
        guard let mark = UIImage(named: "logo_vietqr_v") else { return qr }

        let size = qr.size.width
        let logoSize = size * 0.1
        let pad = logoSize * 0.14
        let center = CGPoint(x: size / 2, y: size / 2)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            qr.draw(in: CGRect(x: 0, y: 0, width: size, height: size))

            let half = logoSize / 2
            let backdrop = CGRect(
                x: center.x - half - pad, y: center.y - half - pad,
                width: logoSize + pad * 2, height: logoSize + pad * 2
            )
            UIColor.white.setFill()
            UIBezierPath(roundedRect: backdrop, cornerRadius: logoSize * 0.22).fill()

            // Giữ tỉ lệ gốc của logo, canh giữa trong ô logoSize.
            let ratio = mark.size.width / mark.size.height
            let markSize = ratio >= 1
                ? CGSize(width: logoSize, height: logoSize / ratio)
                : CGSize(width: logoSize * ratio, height: logoSize)
            mark.draw(in: CGRect(
                x: center.x - markSize.width / 2, y: center.y - markSize.height / 2,
                width: markSize.width, height: markSize.height
            ))
        }
    }
}

private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ShareableText: Identifiable {
    let id = UUID()
    let text: String
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ReceiveQrView(onBack: {})
}
