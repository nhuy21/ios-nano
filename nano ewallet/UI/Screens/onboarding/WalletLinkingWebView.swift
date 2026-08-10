//
//  WalletLinkingWebView.swift
//  nano ewallet
//
//  Mirror WalletLinkingWebViewScreen.kt — nhúng NGUYÊN trang OTP của Bảo Kim
//  (`embed_link` từ onboarding/wallet-linking). Trang này là SPA nhiều bước đã
//  obfuscate, không dựng lại bằng native được: user đọc điều khoản, nhập OTP và xác
//  nhận ngay trên web.
//
//  Bắt trạng thái bằng cách POLL DOM chứ không dựa vào sự kiện điều hướng: trang chuyển
//  bước bằng cách bật class "active" trên các div #step1..#step5 mà KHÔNG tải lại trang,
//  nên `didFinish` chỉ bắn đúng một lần lúc load đầu. #step4 = thành công, #step5 = thất bại.
//

import SwiftUI
import WebKit

struct WalletLinkingWebView: View {

    let embedLink: String
    let onBack: () -> Void
    let onLinked: () -> Void

    /// Webhook Bảo Kim chạy bất đồng bộ sau khi user xác nhận OTP, có thể mất vài giây
    /// mới tạo xong bản ghi ví — thử lại nhiều lần thay vì báo lỗi ngay.
    private static let maxCheckAttempts = 8
    private static let checkInterval: UInt64 = 2_000_000_000
    private static let domPollInterval: UInt64 = 500_000_000

    private enum Stage {
        case loading
        case web
        /// Web đã báo xong (thành công hoặc thất bại) — dừng poll, hiện nút cho user.
        case done
        case checking
    }

    @State private var stage: Stage = .loading
    @State private var checkError: String?
    @State private var controller = WebViewController()

    var body: some View {
        ZStack {
            // Nền trắng phủ cả vùng status bar / home indicator: trang web có dải màu
            // riêng, không che thì lộ hai vệt màu ở trên và dưới.
            Color.white.ignoresSafeArea()

            WebViewContainer(
                url: embedLink,
                controller: controller,
                onPageFinished: { if stage == .loading { stage = .web } }
            )

            if stage == .loading {
                Color.white
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppColor.brand)
            }

            if stage == .done || stage == .checking {
                successOverlay
            }
        }
        .task(id: stage == .web) {
            guard stage == .web else { return }
            await pollForResult()
        }
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Nút quay lại nằm trên dải trắng riêng, không đè lên nội dung web.
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColor.payInk)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Quay lại")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.white)
        }
    }

    // MARK: - Lớp phủ khi web báo xong

    private var successOverlay: some View {
        VStack(spacing: 0) {
            Image("logo_green")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 86, height: 36)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(Color.white)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Text("Xác thực OTP thành công. Bấm Hoàn tất để đồng bộ ví.")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)

                if let checkError {
                    Text(checkError)
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(AppColor.error)
                }

                PrimaryButton(
                    title: "Hoàn tất",
                    loadingTitle: "Đang đồng bộ ví...",
                    isLoading: stage == .checking,
                    action: finish
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.96))
        }
        .allowsHitTesting(true)
    }

    // MARK: - Poll DOM

    /// Trang là SPA nên phải hỏi DOM định kỳ. Dừng ngay khi rời `.web` để không chạy nền.
    private func pollForResult() async {
        let script = """
        (function(){
          var s4 = document.getElementById('step4');
          var s5 = document.getElementById('step5');
          if (s4 && s4.classList.contains('active')) return 'ok';
          if (s5 && s5.classList.contains('active')) return 'fail';
          return '';
        })();
        """
        while stage == .web && !Task.isCancelled {
            let result = await controller.evaluate(script)
            switch result {
            case "ok":
                stage = .done
                return
            case "fail":
                // Vẫn dừng poll và hiện nút: user còn cơ hội bấm đối soát lại thay vì
                // kẹt ở trang web không lối ra.
                checkError = "Kết nối thất bại, vui lòng thử lại."
                stage = .done
                return
            default:
                break
            }
            try? await Task.sleep(nanoseconds: Self.domPollInterval)
        }
    }

    // MARK: - Đối soát ví

    private func finish() {
        guard stage != .checking else { return }
        stage = .checking
        checkError = nil
        Task {
            var lastError: String?
            for attempt in 1...Self.maxCheckAttempts {
                do {
                    try await WalletService.checkWalletInfoFromBaoKim()
                    // fullName ở BE vừa được webhook Bảo Kim cập nhật — refresh token để
                    // lấy tên mới. Best-effort, lỗi ở đây không chặn vào ví.
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
            stage = .done
            checkError = lastError ?? "Chưa nhận được xác nhận từ Bảo Kim, vui lòng thử lại"
        }
    }
}

// MARK: - Cầu nối WKWebView

/// Giữ tham chiếu tới `WKWebView` để chạy JS từ phía SwiftUI. Dùng chung cho cả màn liên
/// kết ví lẫn màn ký thoả thuận.
@MainActor
final class WebViewController {
    weak var webView: WKWebView?

    func evaluate(_ script: String) async -> String {
        guard let webView else { return "" }
        let value = try? await webView.evaluateJavaScript(script)
        return (value as? String) ?? ""
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let url: String
    let controller: WebViewController
    let onPageFinished: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageFinished: onPageFinished) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        // Trang đã khai báo meta viewport width=device-width — để WebView tự co giãn
        // sẽ hiểu nhầm là viewport desktop rồi thu nhỏ, vỡ bố cục mobile.
        webView.scrollView.bouncesZoom = false

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
            // Đồng bộ nền web với app: các container ngoài + footer về trắng để bỏ dải
            // màu lộ trên/dưới thẻ khi màn hẹp; .modal bỏ viền và đổ bóng cho phẳng liền nền.
            let css = "html,body,.container,.wrapper,.page,footer,.footer{background:#fff !important;}"
                + ".modal{border:none !important;box-shadow:none !important;}"
            let script = """
            (function(){
              var s = document.createElement('style');
              s.innerHTML = '\(css)';
              document.head.appendChild(s);
            })();
            """
            webView.evaluateJavaScript(script)
            onPageFinished()
        }
    }
}
