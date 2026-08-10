//
//  PrivacyScreenOverlay.swift
//  nano ewallet
//
//  Che kín màn hình khi app rời foreground (background/inactive) — iOS chụp ảnh y hệt
//  màn hình đang hiển thị để làm thẻ preview App Switcher NGAY tại khoảnh khắc đó, không
//  hỏi ý app. Không che thì preview lộ số dư/số tài khoản/giao dịch thật cho bất kỳ ai
//  đang cầm máy đã mở khóa, kể cả không mở app — chỉ cần vuốt lên xem App Switcher.
//
//  `.inactive` (không chỉ `.background`) BẮT BUỘC phải che: iOS chụp ảnh preview ngay khi
//  chuyển sang inactive (vd lúc vừa bấm Home, trước khi kịp sang background), che muộn hơn
//  là ảnh đã chụp xong.
//

import SwiftUI

struct PrivacyScreenOverlay: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if scenePhase != .active {
            AppColor.brand
                .ignoresSafeArea()
                .overlay {
                    Image("logo_main")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                }
                .transition(.identity)
        }
    }
}

/// Theo dõi tiền về sau khi nạp ví qua "Nạp ví nhanh".
///
/// Vấn đề: nạp xong quay lại app thì số dư CHƯA lên ngay — tiền phải đi NAPAS -> Bảo Kim ->
/// webhook về BE -> BE bắn push. Người dùng không biết đang chờ gì nên dễ tưởng nạp hụt.
///
/// Cách xử lý: hiện banner "đang chờ xác nhận", vừa QUAN SÁT số dư (bắt được push ngay khi
/// tới) vừa gọi lại API mỗi 3s làm dự phòng cho máy tắt thông báo. Quá 60s thì đối soát thẳng
/// Bảo Kim một lần; vẫn không thấy thì hiện banner cam kèm nút Đồng bộ — KHÔNG ẩn im lặng,
/// vì người dùng đã chuyển tiền thật, im lặng khiến họ tưởng mất tiền.
///
/// Đặt MỘT lần ở gốc cây view để hiện xuyên suốt mọi màn.
@MainActor
struct TopUpWatcher: View {

    /// Nhịp gọi lại API dự phòng và thời hạn chờ trước khi chuyển sang đối soát.
    private static let pollInterval: UInt64 = 3_000_000_000
    private static let timeout: Double = 60

    @StateObject private var deepLink = DeepLinkStore.shared
    @StateObject private var wallet = WalletStore.shared
    @StateObject private var authStore = AuthStore.shared

    @State private var waiting = false
    @State private var arrivedAmount: Int64?
    @State private var timedOut = false
    @State private var syncing = false
    /// Đã báo "tiền về" cho lượt nạp này chưa. Luồng chờ chính và nút Đồng bộ chạy SONG SONG
    /// nên thiếu cờ này thì cả hai cùng báo, banner hiện hai lần.
    @State private var settled = false
    @State private var watchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if waiting || arrivedAmount != nil || timedOut {
                banner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: waiting)
        .animation(.easeInOut(duration: 0.25), value: arrivedAmount)
        .animation(.easeInOut(duration: 0.25), value: timedOut)
        .onChangeCompat(of: deepLink.pendingTopUpReturn, initial: true) { _, pending in
            guard pending else { return }
            deepLink.consumeTopUpReturn()
            startWatching()
        }
        // Đăng xuất -> dừng ngay. View này sống ở gốc nên không tự bị huỷ khi về màn Login,
        // không dừng tay thì vòng chờ của tài khoản cũ vẫn chạy và banner vẫn hiện.
        .onChangeNewCompat(of: authStore.sessionRevision) { _ in
            watchTask?.cancel()
            resetState()
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var banner: some View {
        HStack(spacing: 10) {
            if let arrivedAmount {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                Text("Đã nạp +\(Int(arrivedAmount).vndFormatted)")
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(.white)
            } else if timedOut {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.white)
                Text("Chưa thấy tiền về")
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(.white)
                Button {
                    Task { await syncNow() }
                } label: {
                    Text(syncing ? "Đang kiểm tra..." : "Đồng bộ")
                        .font(AppFont.beVietnamPro(12, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.22), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(syncing)
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
                Text("Đang chờ xác nhận tiền về...")
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(bannerColor, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var bannerColor: Color {
        if arrivedAmount != nil { return AppColor.brand }
        if timedOut { return Color(hex: 0xE58A00) }
        return AppColor.payInk
    }

    // MARK: - Luồng chờ

    private func startWatching() {
        watchTask?.cancel()
        resetState()

        // Không có mốc so sánh (vd app bị kill lúc đang ở app ngân hàng nên state mất) thì
        // không kết luận được gì đáng tin — dừng hẳn thay vì báo bừa. Push và lần mở màn sau
        // vẫn cập nhật số dư như thường.
        guard AuthStore.shared.accessToken != nil,
              let before = deepLink.balanceBeforeTopUp else { return }

        waiting = true
        watchTask = Task { await watch(before: before) }
    }

    private func watch(before: Int64) async {
        let arrived = await waitForBalanceIncrease(over: before)

        if Task.isCancelled { return }

        if let arrived {
            deepLink.clearTopUpBaseline()
            if markArrived(arrived) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled { arrivedAmount = nil }
            }
            return
        }

        // Hết hạn chờ -> đối soát thẳng Bảo Kim ĐÚNG một lần. Đắt hơn nhưng không phụ thuộc
        // webhook nên cứu được đúng trường hợp webhook lỗi.
        if await syncFromBaoKim(before: before) {
            deepLink.clearTopUpBaseline()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { arrivedAmount = nil }
            return
        }

        guard !Task.isCancelled else { return }
        // GIỮ nguyên mốc ở nhánh này — nút Đồng bộ trên banner còn cần để so sánh.
        waiting = false
        timedOut = true
    }

    /// Chờ số dư vượt `before`, tối đa 60s. Trả `nil` nếu hết giờ.
    ///
    /// Chạy song song hai việc và lấy việc nào xong trước:
    ///  - QUAN SÁT `balance`: bắt được thay đổi ngay từ MỌI nguồn, kể cả push (push gọi
    ///    `setBalance`). Chỉ dựa vào poll thì push về giữa hai nhịp phải chờ thêm 3s.
    ///  - GỌI LẠI API mỗi 3s: dự phòng cho máy không nhận được push.
    private func waitForBalanceIncrease(over before: Int64) async -> Int64? {
        await withTaskGroup(of: Int64?.self) { group in
            // Nhánh QUAN SÁT: bắt số dư đổi NGAY từ mọi nguồn, kể cả push (push gọi thẳng
            // `setBalance`). Chỉ dựa vào nhịp gọi lại thì push về giữa hai nhịp phải chờ thêm.
            //
            // Tự chốt thời hạn bên trong bằng `Task.sleep` xen kẽ chứ không chờ bị huỷ:
            // `$balance.values` là publisher KHÔNG BAO GIỜ tự kết thúc, mà `withTaskGroup`
            // chỉ trả về khi mọi nhánh con đã xong — trông chờ vào `cancelAll()` để thoát
            // khỏi `for await` này là chỗ dễ treo cả luồng.
            group.addTask { @MainActor in
                let deadline = Date().addingTimeInterval(Self.timeout)
                while !Task.isCancelled, Date() < deadline {
                    if let now = WalletStore.shared.balance, now > before {
                        return now - before
                    }
                    // Nhịp kiểm tra dày (0,2s) nên độ trễ so với push gần như không thấy,
                    // mà vẫn là vòng lặp có điểm dừng rõ ràng.
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                return nil
            }
            // Nhánh GIỤC: gọi lại API cho máy không nhận được push.
            group.addTask { @MainActor in
                let deadline = Date().addingTimeInterval(Self.timeout)
                while !Task.isCancelled, Date() < deadline {
                    try? await Task.sleep(nanoseconds: Self.pollInterval)
                    guard !Task.isCancelled else { return nil }
                    await WalletStore.shared.refresh(force: true)
                }
                return nil
            }

            // Duyệt CẢ kết quả nil chứ không lọc bỏ: hết giờ thì cả hai nhánh cùng trả nil,
            // lọc đi là vòng lặp đứng chờ mãi một giá trị khác nil không bao giờ tới — banner
            // quay vĩnh viễn và phần đối soát bên dưới thành code chết.
            var result: Int64?
            for await value in group {
                if let value {
                    result = value
                    break
                }
            }
            group.cancelAll()
            return result
        }
    }

    /// Đối soát thẳng với Bảo Kim rồi đọc lại số dư. `true` nếu thấy tiền đã về.
    private func syncFromBaoKim(before: Int64) async -> Bool {
        _ = await WalletStore.shared.syncWithBaoKim()
        guard let now = WalletStore.shared.balance, now > before else { return false }
        return markArrived(now - before)
    }

    /// Nút Đồng bộ trên banner cam.
    private func syncNow() async {
        guard !syncing, let before = deepLink.balanceBeforeTopUp else { return }
        syncing = true
        defer { syncing = false }
        if await syncFromBaoKim(before: before) {
            deepLink.clearTopUpBaseline()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            arrivedAmount = nil
        }
    }

    /// Báo tiền đã về đúng MỘT lần, dù được gọi từ luồng chờ hay từ nút Đồng bộ.
    @discardableResult
    private func markArrived(_ delta: Int64) -> Bool {
        guard !settled else { return false }
        settled = true
        arrivedAmount = delta
        waiting = false
        timedOut = false
        return true
    }

    private func resetState() {
        waiting = false
        arrivedAmount = nil
        timedOut = false
        syncing = false
        settled = false
    }
}
