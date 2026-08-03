//
//  AgreementWebView.swift
//  nano ewallet
//
//  Mirror AgreementWebViewScreen.kt — thoả thuận mở ví điện tử.
//
//  Giao diện dựng NATIVE lại y trang /embed/contracts-confirmation của Bảo Kim, còn
//  WebView thật thì ẨN (1pt, trong suốt) chạy nền.
//
//  Vì sao phải làm vòng vo vậy: trang confirm là form POST thuần, không có API cho đối
//  tác gọi, và mỗi lần gửi phải kèm CSRF token gắn với phiên của chính trang đó. App
//  không tự dựng được request. Nên: người dùng tick và bấm "Xác nhận" trên giao diện
//  native → app tiêm JS tick 2 ô rồi submit form trong WebView ẩn → web tự gửi như bình
//  thường → trang tải xong thì soi DOM tìm `.success-screen` để biết chắc đã ký xong →
//  đối soát ví → báo về.
//

import SwiftUI
import WebKit

struct AgreementWebView: View {

    let embedLink: String
    let onBack: () -> Void
    let onLinked: () -> Void

    /// Webhook Bảo Kim chạy bất đồng bộ sau khi ký, có thể mất vài giây mới tạo xong ví.
    private static let maxCheckAttempts = 8
    private static let checkInterval: UInt64 = 2_000_000_000

    private enum Stage {
        case loading
        case form
        case submitting
        /// Web đã báo ký xong — chờ người dùng bấm "Hoàn tất" mới đối soát.
        case success
        case checking
    }

    // Bố cục và sắc độ theo trang của Bảo Kim, nhưng ĐỔI tông xanh nước biển sang xanh lá
    // của app: màn này nằm giữa luồng mở ví của Ví nano, để nguyên xanh Bảo Kim thì lạc
    // hẳn khỏi các màn trước sau. Giữ đúng tương quan đậm/nhạt: xanh đậm -> brand, xanh
    // rất nhạt -> brandSoft.
    private enum Bk {
        static let pageBg = Color(hex: 0xF5F7FA)
        static let accent = AppColor.brand
        static let accentSoft = AppColor.brandSoft
        static let ink = Color(hex: 0x1A1A2E)
        static let listText = Color(hex: 0x444444)
        static let label = Color(hex: 0x999999)
        static let divider = Color(hex: 0xF2F2F2)
        static let checkBorder = Color(hex: 0xBBBBBB)
        static let successGreen = Color(hex: 0x27AE60)
        static let errorRed = Color(hex: 0xC0392B)
    }

    private static let prohibitedItems = [
        "Thực hiện các giao dịch cho các mục đích rửa tiền, tài trợ khủng bố, tài trợ phổ biến vũ khí huỷ diệt hàng loạt, lừa đảo, gian lận và các hành vi vi phạm pháp luật khác.",
        "Thực hiện các giao dịch mua bán hàng hóa/dịch vụ, giao dịch thanh toán bị cấm/không được phép, vi phạm quy định của pháp luật Việt Nam.",
        "Thực hiện các giao dịch cho mục đích thanh toán cho các website, ứng dụng cung cấp trò chơi điện tử chưa được cấp phép phát hành tại Việt Nam.",
        "Mở hoặc duy trì tài khoản Ví điện tử Baokim nặc danh, mạo danh; mua, bán, thuê, cho thuê, mượn, cho mượn Ví điện tử Baokim; lấy cắp, thông đồng để lấy cắp, mua, bán thông tin Ví điện tử Baokim.",
        "Cung cấp không trung thực thông tin có liên quan đến việc sử dụng Ví điện tử Baokim.",
        "Thực hiện các giao dịch/hành vi không được phép khác theo quy định pháp luật tuỳ từng thời điểm.",
    ]

    /// Câu dẫn danh sách hành vi bị cấm — in đậm riêng "KHÔNG ĐƯỢC" bằng
    /// `AttributedString` (thay `Text + Text` đã deprecated ở iOS 26).
    private var prohibitedIntro: AttributedString {
        var result = AttributedString("Quý khách hàng ")
        var emphasis = AttributedString("KHÔNG ĐƯỢC")
        emphasis.font = AppFont.beVietnamPro(14, .bold)
        result += emphasis
        result += AttributedString(" sử dụng Ví điện tử Baokim để:")
        return result
    }

    @State private var stage: Stage = .loading
    @State private var agreeNoViolation = false
    @State private var agreeTerms = false
    @State private var errorMessage: String?
    @State private var controller = WebViewController()
    /// Hai link PDF đọc từ chính DOM — chúng gắn token/phiên nên không ghi cứng được.
    @State private var policyUrl: String?
    @State private var termsUrl: String?

    private var canSubmit: Bool { agreeNoViolation && agreeTerms && stage == .form }

    var body: some View {
        ZStack {
            // WebView ẩn: 1pt, trong suốt — chỉ để giữ phiên/CSRF và gửi form hộ.
            HiddenWebView(
                url: embedLink,
                controller: controller,
                onPageFinished: handlePageFinished
            )
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)

            switch stage {
            case .loading:
                ProgressView().progressViewStyle(.circular).tint(Bk.accent)
            case .success, .checking:
                successView
            case .form, .submitting:
                formView
            }
        }
        // Nền đặt bằng `.background` chứ KHÔNG làm một con của ZStack: con nào
        // `ignoresSafeArea` thì ZStack báo vùng an toàn bằng 0 cho cả các con còn lại.
        .background(Bk.pageBg.ignoresSafeArea())
    }

    // MARK: - Form

    private var formView: some View {
        VStack(spacing: 0) {
            // Phần đầu nằm NGOÀI vùng cuộn: ScrollView của iOS 26 cho nội dung chạy ngầm
            // dưới thanh trạng thái nên để bên trong là tiêu đề đè lên đồng hồ, mà chèn
            // `safeAreaPadding` để chặn thì vùng cuộn lại mở ra ở giữa thẻ. Ở ngoài thì
            // VStack tự tôn trọng vùng an toàn. Android để phần này cuộn theo, nhưng nó
            // chỉ là logo + tiêu đề nên ghim lại không mất gì.
            header
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 0) {
                    prohibitedCard
                        .padding(.top, 20)

                    commitmentCard
                        .padding(.top, 14)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFont.beVietnamPro(13))
                            .foregroundStyle(Bk.errorRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Button(action: submitViaWeb) {
                Text(stage == .submitting ? "Đang gửi xác nhận..." : "Xác nhận")
                    .font(AppFont.beVietnamPro(16, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Bk.accent.opacity(canSubmit ? 1 : 0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Bk.accentSoft)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Bk.accent)
                }

            Text("Thỏa thuận sử dụng\nVí điện tử")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(Bk.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            HStack(spacing: 5) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Bk.accent)
                Text("Vui lòng đọc kỹ các điều khoản trước khi tiếp tục")
                    .font(AppFont.beVietnamPro(11.5))
                    .foregroundStyle(Bk.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Bk.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 12)
        }
        // 8 chứ không phải 16: ScrollView đã tự chèn sẵn một khoảng lề trên.
        .padding(.top, 8)
    }

    private var prohibitedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CÁC HÀNH VI KHÔNG ĐƯỢC THỰC HIỆN KHI MỞ VÀ SỬ DỤNG VÍ ĐIỆN TỬ BAOKIM")
                .font(AppFont.beVietnamPro(11, .bold))
                .foregroundStyle(Bk.label)
                .tracking(0.8)
                .fixedSize(horizontal: false, vertical: true)

            // AttributedString thay `Text + Text` (deprecated iOS 26) — vẫn là MỘT `Text`
            // nên đoạn dài tự wrap đúng.
            Text(prohibitedIntro)
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(Bk.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.prohibitedItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 0) {
                        Text("•  ")
                        Text(item)
                    }
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(Bk.listText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 2, y: 1)
    }

    private var commitmentCard: some View {
        VStack(spacing: 0) {
            checkboxRow(isChecked: $agreeNoViolation) {
                Text("Tôi cam kết không sử dụng Ví điện tử Baokim để thực hiện các hành vi vi phạm pháp luật.")
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(Bk.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(Bk.divider)
                .frame(height: 1)
                .padding(.vertical, 12)

            checkboxRow(isChecked: $agreeTerms) {
                // Một `Text` duy nhất để cả cụm chảy như đoạn văn, tự xuống dòng theo bề
                // rộng. Tách thành HStack thì mỗi link thành một khối, ngắt dòng cứng và
                // chữ "và" bị đẩy lung tung.
                Text(termsAttributed)
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(Bk.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 2, y: 1)
    }

    /// Câu cam kết có 2 link nhúng. Link mở ra trình duyệt ngoài (mirror `ACTION_VIEW`
    /// bên Android) — 2 URL này đọc từ chính DOM của trang vì chúng gắn token/phiên.
    private var termsAttributed: AttributedString {
        var result = AttributedString("Tôi đồng ý với ")
        result.append(linkRun("Chính sách xử lý dữ liệu", url: policyUrl))
        result.append(AttributedString(" và "))
        result.append(linkRun("Điều khoản sử dụng", url: termsUrl))
        return result
    }

    /// Luôn tô xanh + gạch chân để hai cụm này nhìn ra ngay là bấm được, kể cả lúc trang
    /// chưa tải xong nên chưa đọc được URL — gắn `link` sau, khi đã có.
    ///
    /// Hai cụm trỏ HAI URL khác nhau: `policyUrl` là chính sách xử lý dữ liệu, `termsUrl`
    /// là điều khoản sử dụng, đọc theo thứ tự xuất hiện trong DOM.
    private func linkRun(_ title: String, url: String?) -> AttributedString {
        var run = AttributedString(title)
        run.foregroundColor = Bk.accent
        run.underlineStyle = .single
        if let url, let link = URL(string: url) {
            run.link = link
        }
        return run
    }

    private func checkboxRow<Content: View>(
        isChecked: Binding<Bool>, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { isChecked.wrappedValue.toggle() } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isChecked.wrappedValue ? Bk.accent : Color.white)
                    .frame(width: 20, height: 20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                isChecked.wrappedValue ? Bk.accent : Bk.checkBorder, lineWidth: 1.5
                            )
                    }
                    .overlay {
                        if isChecked.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)

            content()

            Spacer(minLength: 0)
        }
    }

    // MARK: - Thành công

    private var successView: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Bk.successGreen.opacity(0.12))
                            .frame(width: 64, height: 64)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Bk.successGreen)
                            }

                        Text("Xác nhận thành công!")
                            .font(AppFont.beVietnamPro(18, .bold))
                            .foregroundStyle(Bk.ink)
                            .padding(.top, 14)

                        Text("Bạn đã đồng ý với các điều khoản và thỏa thuận sử dụng Ví điện tử Bảo Kim.")
                            .font(AppFont.beVietnamPro(14))
                            .foregroundStyle(Bk.listText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)

                        Text("Thông tin xác nhận của bạn đã được ghi nhận.")
                            .font(AppFont.beVietnamPro(13))
                            .foregroundStyle(Bk.label)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.07), radius: 2, y: 1)
                    .padding(.top, 20)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFont.beVietnamPro(13))
                            .foregroundStyle(Bk.errorRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Button(action: runCheckWalletInfo) {
                Text(stage == .checking ? "Đang đồng bộ ví..." : "Hoàn tất")
                    .font(AppFont.beVietnamPro(16, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Bk.accent.opacity(stage == .checking ? 0.45 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(stage == .checking)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Nghiệp vụ

    private func handlePageFinished() {
        switch stage {
        case .loading:
            Task {
                await readPdfLinks()
                stage = .form
            }
        case .submitting:
            Task { await probeSuccess() }
        default:
            break
        }
    }

    /// Đọc href của 2 link trong form: [0] chính sách dữ liệu, [1] điều khoản sử dụng.
    private func readPdfLinks() async {
        let script = """
        (function(){
          var a = document.querySelectorAll('.checkbox-text a');
          return (a.length >= 2) ? (a[0].href + '|' + a[1].href) : '';
        })();
        """
        let raw = await controller.evaluate(script).replacingOccurrences(of: "\\/", with: "/")
        let parts = raw.components(separatedBy: "|")
        guard parts.count == 2 else { return }
        policyUrl = parts[0].isEmpty ? nil : parts[0]
        termsUrl = parts[1].isEmpty ? nil : parts[1]
    }

    /// Tick 2 ô rồi submit form ngay trong WebView, để chính trang web gửi đi kèm CSRF.
    private func submitViaWeb() {
        guard canSubmit else { return }
        stage = .submitting
        errorMessage = nil
        let script = """
        (function(){
          var c1 = document.getElementById('agreeCheckbox1');
          var c2 = document.getElementById('agreeCheckbox2');
          var f  = document.getElementById('confirmForm');
          if (!c1 || !c2 || !f) { return '0'; }
          c1.checked = true; c2.checked = true;
          if (typeof f.requestSubmit === 'function') { f.requestSubmit(); } else { f.submit(); }
          return '1';
        })();
        """
        Task {
            let result = await controller.evaluate(script)
            if result != "1" {
                // Không thấy form/checkbox — trang đổi cấu trúc. Về form để thử lại.
                stage = .form
                errorMessage = "Không gửi được xác nhận, vui lòng thử lại"
            }
            // Gửi được thì đợi trang tải xong lần kế rồi soi `.success-screen`.
        }
    }

    private func probeSuccess() async {
        let script = "(function(){return document.querySelector('.success-screen') ? '1' : '0';})();"
        let result = await controller.evaluate(script)
        if result == "1" {
            stage = .success
        } else {
            stage = .form
            errorMessage = "Xác nhận thoả thuận chưa thành công, vui lòng thử lại"
        }
    }

    private func runCheckWalletInfo() {
        guard stage != .checking else { return }
        stage = .checking
        errorMessage = nil
        Task {
            var lastError: String?
            for attempt in 1...Self.maxCheckAttempts {
                do {
                    try await WalletService.checkWalletInfoFromBaoKim()
                    // Tên đầy đủ vừa được webhook cập nhật ở BE — lấy token mới cho khớp.
                    // Best-effort, lỗi ở đây không chặn vào ví.
                    _ = try? await AuthService.refresh()
                    onLinked()
                    return
                } catch let error as APIError {
                    lastError = error.message
                } catch {
                    lastError = "Đối soát ví thất bại"
                }
                if attempt < Self.maxCheckAttempts {
                    try? await Task.sleep(nanoseconds: Self.checkInterval)
                }
            }
            stage = .success
            errorMessage = lastError ?? "Chưa nhận được xác nhận từ Bảo Kim, vui lòng thử lại"
        }
    }
}

/// WebView chạy nền, không hiện lên — chỉ giữ phiên và thực thi JS.
private struct HiddenWebView: UIViewRepresentable {
    let url: String
    let controller: WebViewController
    let onPageFinished: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageFinished: onPageFinished) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        if let link = URL(string: url) {
            webView.load(URLRequest(url: link))
        }
        controller.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onPageFinished: () -> Void

        init(onPageFinished: @escaping () -> Void) {
            self.onPageFinished = onPageFinished
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onPageFinished()
        }
    }
}
