//
//  DeviceSecurityCheck.swift
//  nano ewallet
//
//  Kiểm tra thiết bị có an toàn để chạy app tài chính không,
//  theo Thông tư 77/2025/TT-NHNN (hiệu lực 1/3/2026): ví điện tử/app ngân hàng bắt buộc từ
//  chối chạy trên thiết bị đã jailbreak, có debugger đính kèm, hoặc chạy trên giả lập.
//
//  KHÔNG bắt được 100% (jailbreak ẩn kỹ bằng Liberty Lite/Shadow, hook lại chính hàm kiểm
//  tra...) — đây là lớp phòng thủ "chặn số đông", làm tăng chi phí tấn công chứ không phải
//  giải pháp tuyệt đối. Mỗi lượt chạy chỉ vài mili-giây (stat vài file + gọi syscall nhẹ,
//  không I/O nặng, không gọi mạng) nên gọi lại nhiều lần trong một phiên không đáng kể.
//
//  Không kiểm "USB Debugging": iOS không có công tắc tương đương ADB. Developer Mode
//  (iOS 16+) KHÔNG phải dấu hiệu jailbreak — máy dev bình thường bật nó để chạy app từ
//  Xcode, chặn theo cái đó là chặn nhầm cả đội phát triển và tester TestFlight.
//

import Foundation
import SwiftUI
// `MachO` cho `_dyld_image_count`/`_dyld_get_image_name`, `Darwin` cho `sysctl`/`P_TRACED`.
import MachO
#if canImport(Darwin)
import Darwin
#endif

enum DeviceSecurityCheck {

    enum Risk {
        case jailbroken
        case debuggerAttached
        case simulator
    }

    /// Danh sách rủi ro phát hiện được — rỗng nghĩa là thiết bị qua hết các kiểm tra.
    static func detect() -> [Risk] {
        var risks: [Risk] = []
        // Simulator CHỈ tính là rủi ro ở bản Release: bản Debug chạy Simulator suốt ngày,
        // chặn luôn thì không ai dev được. Bản Release lọt lên Simulator nghĩa là ai đó đang
        // phân tích app, không phải người dùng thật.
        #if !DEBUG
        if isSimulator { risks.append(.simulator) }
        #endif
        if isJailbroken { risks.append(.jailbroken) }
        if isDebuggerAttached { risks.append(.debuggerAttached) }
        return risks
    }

    // ── Jailbreak ─────────────────────────────────────────────────────────
    // Không có API chính thức "isJailbroken()" — kết hợp ba dấu hiệu, không dấu hiệu nào
    // chắc chắn riêng lẻ nhưng cùng lúc thì khả năng jailbreak rất cao.
    //
    // CỐ Ý KHÔNG dùng `fork()` dù đó là dấu hiệu mạnh: hàm này bị đánh dấu unavailable trong
    // SDK iOS (không compile được), và kể cả lách được thì App Store review soi symbol tạo
    // tiến trình. Ngoài ra gọi `fork()` trong tiến trình đa luồng như app UIKit rất dễ treo
    // tiến trình con (chỉ được gọi hàm async-signal-safe trước `_exit`), mà treo lúc khởi
    // động thì watchdog giết app.
    static var isJailbroken: Bool {
        // Simulator ghi được ra ngoài sandbox nên luôn "vi phạm" — loại trừ trước, không thì
        // không ai dev được.
        guard !isSimulator else { return false }
        return hasJailbreakFiles
            || canWriteOutsideSandbox
            || hasSuspiciousDynamicLibraries
    }

    /// Đường dẫn của các công cụ jailbreak phổ biến. Dò được thì gần như chắc chắn, nhưng dễ
    /// bị ẩn nhất trong ba cách — nên chỉ là một vế trong `||`.
    ///
    /// KHÔNG liệt `/bin/bash` và `/usr/bin/ssh`: hai file này CÓ THẬT trên macOS, nên nếu
    /// target build cho Mac Catalyst hoặc chạy "Designed for iPad" trên máy Apple Silicon thì
    /// mọi người dùng Mac bị chặn oan.
    private static let jailbreakPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
        "/private/var/lib/cydia",
        "/var/jb",
    ]

    private static var hasJailbreakFiles: Bool {
        jailbreakPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// App trong sandbox KHÔNG ghi được ra ngoài thư mục của mình. Ghi được `/private` nghĩa
    /// là sandbox đã bị gỡ. Dọn file ngay sau khi thử để không để lại rác.
    private static var canWriteOutsideSandbox: Bool {
        let path = "/private/\(UUID().uuidString)"
        do {
            try "check".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// Thư viện của công cụ hook/instrument (Frida, Cydia Substrate...) nạp vào tiến trình.
    /// Bắt được cả trường hợp file jailbreak đã bị ẩn nhưng công cụ hook vẫn đang chạy.
    private static var hasSuspiciousDynamicLibraries: Bool {
        let markers = [
            "MobileSubstrate", "SubstrateLoader", "SubstrateInserter",
            "libhooker", "libsubstitute", "TweakInject",
            "FridaGadget", "frida", "cynject", "cycript",
        ]
        for index in 0..<_dyld_image_count() {
            guard let raw = _dyld_get_image_name(index) else { continue }
            let name = String(cString: raw)
            if markers.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
                return true
            }
        }
        return false
    }

    // ── Debugger ──────────────────────────────────────────────────────────
    /// `sysctl` hỏi kernel xem tiến trình có cờ `P_TRACED` không — cách chuẩn để biết có ai
    /// đang attach debugger (lldb, Frida) vào app.
    ///
    /// Bỏ qua ở bản DEBUG: chính Xcode luôn attach debugger khi chạy từ máy dev, không loại
    /// trừ thì không ai build chạy được.
    static var isDebuggerAttached: Bool {
        #if DEBUG
        return false
        #else
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
        #endif
    }

    // ── Simulator ─────────────────────────────────────────────────────────
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Chặn app khi thiết bị không an toàn

/// Bọc TOÀN BỘ app: phát hiện rủi ro thì thay hẳn nội dung bằng màn cảnh báo, không cho vào
/// bất kỳ chức năng nào — mirror `SecurityGate` bên Android.
///
/// Kiểm lại mỗi khi app trở lại foreground: người dùng có thể tắt jailbreak/gỡ debugger rồi
/// mở lại, và ngược lại — bật giữa chừng thì lần quay lại kế tiếp phải chặn được.
struct SecurityGate<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.scenePhase) private var scenePhase
    /// Mặc định KHÔNG chặn, để `detect()` chạy trong `.onChangeCompat` bên dưới. Chạy ngay
    /// tại đây (`= !detect().isEmpty`) là chạy đồng bộ trong lúc dựng `WindowGroup`: stat
    /// một loạt file + thử ghi ra `/private` (đường này còn sinh log vi phạm sandbox, tốn
    /// hàng chục ms) + duyệt hết dyld — đủ để watchdog giết app lúc khởi động.
    @State private var isBlocked = false

    var body: some View {
        Group {
            if isBlocked {
                SecurityBlockedView()
            } else {
                content()
            }
        }
        // `initial: true` để chạy lượt đầu ngay khi view xuất hiện — thay cho việc kiểm lúc
        // khởi tạo state.
        .onChangeCompat(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            isBlocked = !DeviceSecurityCheck.detect().isEmpty
        }
    }
}

/// Màn chặn toàn màn hình. KHÔNG có nút "vào tiếp" — điều kiện chặn chỉ hết khi người dùng
/// thật sự gỡ jailbreak/debugger rồi mở lại app.
///
/// Cũng không có nút "Đóng ứng dụng" như bản Android: iOS coi app tự gọi `exit()` là crash,
/// và Apple từ chối app có nút thoát (Human Interface Guidelines). Người dùng tự vuốt đóng.
private struct SecurityBlockedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(AppColor.errorSoft)
                .frame(width: 88, height: 88)
                .overlay {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColor.error)
                }

            Text("Thiết bị không an toàn")
                .font(AppFont.beVietnamPro(20, .bold))
                .foregroundStyle(AppColor.payInk)

            Text(
                """
                Ví nano không thể chạy trên thiết bị đã bị can thiệp (jailbreak) hoặc đang bị \
                gỡ lỗi, theo quy định về an toàn cho ứng dụng tài chính.

                Vui lòng dùng thiết bị nguyên bản để tiếp tục.
                """
            )
            .font(AppFont.beVietnamPro(14))
            .foregroundStyle(AppColor.payMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .screenBackground(Color.white, alignment: .center)
    }
}
