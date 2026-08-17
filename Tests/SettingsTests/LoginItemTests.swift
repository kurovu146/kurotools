import XCTest
@testable import Settings

/// Bản giả để test logic bật/tắt. `SMAppService` thật đăng ký với launchd —
/// gọi nó trong test sẽ sửa máy đang chạy. `state` là `var` công khai để test
/// gán thẳng `.requiresApproval` — trạng thái đó không đi qua `setEnabled`.
private final class FakeLoginItem: LoginItemControlling {
    var state: LoginItemState = .off
    var failNext = false
    func setEnabled(_ on: Bool) throws {
        if failNext { throw NSError(domain: "test", code: 1) }
        state = on ? .on : .off
    }
}

/// Cả hai test đọc file thật bên dưới cần leo từ file test này lên gốc repo.
private func repoRoot(from testFile: String = #filePath) -> URL {
    URL(fileURLWithPath: testFile)
        .deletingLastPathComponent() // LoginItemTests.swift -> SettingsTests/
        .deletingLastPathComponent() // SettingsTests/ -> Tests/
        .deletingLastPathComponent() // Tests/ -> repo root
}

final class LoginItemTests: XCTestCase {
    func testTogglingOnAndOff() throws {
        let item = FakeLoginItem()
        try item.setEnabled(true)
        XCTAssertTrue(item.isEnabled)
        try item.setEnabled(false)
        XCTAssertFalse(item.isEnabled)
    }

    func testAFailedRegistrationLeavesTheStateUnchanged() {
        let item = FakeLoginItem()
        item.failNext = true
        XCTAssertThrowsError(try item.setEnabled(true))
        XCTAssertFalse(item.isEnabled,
                       "trạng thái phải đọc từ hệ thống, không phải từ ý định của UI")
    }

    func testARequiresApprovalStateIsReportedAsSuchNotAsOff() {
        // `register()` không throw khi macOS xếp hàng "background item added";
        // UI đọc lại `state` phải thấy đúng `.requiresApproval`, không được
        // gộp chung với `.off` rồi bật công tắc về lại vị trí cũ trong im lặng.
        let item = FakeLoginItem()
        item.state = .requiresApproval
        XCTAssertEqual(item.state, .requiresApproval)
        XCTAssertFalse(item.isEnabled,
                       "chờ duyệt chưa phải bật, nhưng không được lẫn với off")
    }

    func testThePlistNameMatchesTheLabelInsideTheBundledPlist() throws {
        // Sai tên file = SMAppService im lặng không tìm thấy agent — nên test này phải đọc
        // THẬT file plist sẽ được bundle, không so hai literal trong code Swift với nhau.
        let plistURL = repoRoot().appendingPathComponent("Sources/KuroTools/LaunchAgent.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        let label = try XCTUnwrap(plist["Label"] as? String)
        XCTAssertEqual(label, "com.kuro.kurotools.app")
        XCTAssertEqual(SMAppServiceLoginItem.plistName, "\(label).plist")

        let programArguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertEqual(programArguments.first, "/Applications/KuroTools.app/Contents/MacOS/KuroTools")
    }

    func testTheBundleScriptCopiesThePlistToTheNameSMAppServiceExpects() throws {
        // Fix round 2: đổi MỘT MÌNH tên đích trong bundle-app.sh vẫn để mọi thứ
        // khác xanh (test cũ không đọc script, build/chữ ký không quan tâm tên
        // file). Đọc thật script, bắt dòng `cp` copy plist, ép nó khớp
        // `SMAppServiceLoginItem.plistName` — sai tên = SMAppService không bao
        // giờ tìm thấy agent lúc chạy thật, dù mọi thứ trong CI đều xanh.
        let scriptURL = repoRoot().appendingPathComponent("scripts/bundle-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let copyLine = try XCTUnwrap(
            script.components(separatedBy: .newlines).first {
                $0.hasPrefix("cp ") && $0.contains("LaunchAgent.plist")
            },
            "không tìm thấy dòng `cp ... LaunchAgent.plist` trong bundle-app.sh")

        XCTAssertTrue(
            copyLine.hasSuffix("\(SMAppServiceLoginItem.plistName)\""),
            "đích copy trong bundle-app.sh phải kết thúc bằng đúng " +
            "SMAppServiceLoginItem.plistName (\"\(SMAppServiceLoginItem.plistName)\"); " +
            "dòng thật đọc được: \(copyLine)")

        // Fix wave cuối M2 (FIX 5): NGUỒN cũng phải neo vào "$ROOT". Bản trước
        // dùng đường dẫn tương đối trong một script mà mọi chỗ khác đều tuyệt
        // đối — chạy từ một cwd khác thì `cp` hỏng dưới `set -e`, và nó hỏng
        // SAU khi `rm -rf "$APP"` đã xoá bundle cũ: bản cài biến mất, không có
        // gì thay thế. Test cũ chỉ ràng buộc ĐÍCH nên không thấy gì.
        XCTAssertTrue(
            copyLine.contains("\"$ROOT/Sources/KuroTools/LaunchAgent.plist\""),
            "nguồn copy phải là \"$ROOT/Sources/KuroTools/LaunchAgent.plist\" (tuyệt đối); " +
            "dòng thật đọc được: \(copyLine)")
    }

    // MARK: - Fix wave cuối M2 (FIX 1): hai script cài/gỡ phải nói cùng một thứ tiếng với bundle

    /// `install-app.sh` cũ dựng một LaunchAgent viết tay trỏ vào
    /// `.build/release/KuroTools` — một bản dev chưa ký, dưới một label THỨ BA
    /// (`com.kuro.kurovitals.app`) mà `SMAppService` không biết gì. Bản mới chỉ
    /// còn đưa bundle đã ký vào đúng chỗ `LaunchAgent.plist` trong bundle trỏ
    /// tới. Ràng buộc thật nằm giữa HAI FILE: cài ra chỗ khác thì login item
    /// đăng ký thành công mà launchd khởi động một đường dẫn không tồn tại.
    func testTheInstallScriptsPutTheBundleWhereTheLaunchAgentPointsAt() throws {
        let install = try String(
            contentsOf: repoRoot().appendingPathComponent("scripts/install-app.sh"), encoding: .utf8)
        let destLine = try XCTUnwrap(
            install.components(separatedBy: .newlines).first { $0.hasPrefix("DEST=") },
            "không tìm thấy dòng `DEST=` trong install-app.sh")
        let dest = destLine
            .dropFirst("DEST=".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        let plistURL = repoRoot().appendingPathComponent("Sources/KuroTools/LaunchAgent.plist")
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: try Data(contentsOf: plistURL), format: nil) as? [String: Any])
        let programArguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])

        XCTAssertEqual(
            programArguments.first, "\(dest)/Contents/MacOS/KuroTools",
            "install-app.sh cài vào \(dest) nhưng LaunchAgent trong bundle khởi động " +
            "\(programArguments.first ?? "nil") — login item sẽ trỏ vào một đường dẫn không tồn tại")

        let uninstall = try String(
            contentsOf: repoRoot().appendingPathComponent("scripts/uninstall-app.sh"), encoding: .utf8)
        XCTAssertTrue(
            uninstall.contains("DEST=\"\(dest)\""),
            "uninstall-app.sh phải gỡ đúng bản mà install-app.sh cài (\(dest)); " +
            "bản cũ chỉ biết tới LaunchAgent viết tay và không gỡ được bundle nào cả")
    }

    /// Autostart giờ CHỈ thuộc về `SMAppService` (công tắc trong Settings). Một
    /// script dựng thêm LaunchAgent riêng là dựng lại đúng mối nguy "hai bản
    /// cùng tự chạy lúc đăng nhập" — hai label khác nhau nên launchd không hề
    /// biết chúng là cùng một app.
    ///
    /// Chỉ soi hai script của APP: `install-helper.sh` PHẢI dựng LaunchDaemon
    /// riêng (root, chạy trước khi đăng nhập) và không liên quan gì tới đây.
    func testTheAppScriptsDoNotCreateASecondAutostartMechanism() throws {
        for name in ["install-app.sh", "uninstall-app.sh"] {
            let script = try String(
                contentsOf: repoRoot().appendingPathComponent("scripts/\(name)"), encoding: .utf8)
            XCTAssertFalse(script.contains("RunAtLoad"),
                           "\(name) đang viết một plist autostart của riêng nó")
            XCTAssertFalse(script.contains("launchctl load"),
                           "\(name) đang nạp một LaunchAgent của riêng nó")
            XCTAssertFalse(script.contains("launchctl bootstrap"),
                           "\(name) đang nạp một LaunchAgent của riêng nó")
        }
    }

    /// 🔑 Fix wave cuối M2 (FIX A). Cổng "app vẫn đang chạy" phải đứng TRƯỚC
    /// mọi thao tác phá huỷ, ở CẢ HAI script. `install-app.sh` có nó ngay từ
    /// đầu; `uninstall-app.sh` thì không — nó rơi ra khỏi vòng chờ, `rm -rf`
    /// một bundle đang chạy rồi `launchctl bootout` đúng label đã khởi động
    /// tiến trình đó. `bootout` gửi SIGTERM, và SIGTERM KHÔNG chạy
    /// `applicationWillTerminate` — nơi duy nhất trả quạt về Auto. Quạt kẹt
    /// nguyên RPM ép cuối cùng cho tới khi helper hết TTL, và bundle thì đã
    /// biến mất.
    ///
    /// Không phải đường hiếm: `osascript` cần quyền Automation (Apple Events)
    /// cho terminal đang gọi, một lần từ chối bị `|| true` nuốt mất, nên lần
    /// chạy ĐẦU trên một terminal mới rơi đúng vào đây.
    func testBothAppScriptsRefuseToActWhileTheAppIsStillRunning() throws {
        for name in ["install-app.sh", "uninstall-app.sh"] {
            let lines = try String(
                contentsOf: repoRoot().appendingPathComponent("scripts/\(name)"), encoding: .utf8)
                .components(separatedBy: .newlines)

            // Cổng = lời gọi `pgrep` có `exit 1` ngay sau đó. Neo vào cặp này
            // chứ không vào `exit 1` đầu tiên: chỉ nó mới chứng minh cổng nói
            // về ĐÚNG chuyện "app còn chạy". Hai lời gọi `pgrep` kia (vòng
            // ngoài và vòng chờ) không có `exit 1` theo sau nên không khớp.
            let refusal = try XCTUnwrap(
                lines.indices.first { i in
                    lines[i].contains("pgrep -f \"$DEST/Contents/MacOS/KuroTools\"")
                        && lines[(i + 1)...].prefix(3).contains {
                            $0.trimmingCharacters(in: .whitespaces) == "exit 1"
                        }
                },
                "\(name) không có cổng từ chối nào cho ca app vẫn đang chạy")

            let destructive = lines.enumerated().filter { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("rm ") || trimmed.hasPrefix("cp -R")
                    || trimmed.hasPrefix("launchctl bootout")
            }
            XCTAssertFalse(destructive.isEmpty, "setup: \(name) phải có thao tác phá huỷ để mà gác")
            for (index, line) in destructive {
                XCTAssertGreaterThan(
                    index, refusal,
                    "\(name): dòng \(index + 1) chạy TRƯỚC cổng từ chối (dòng \(refusal + 1)) — " +
                    "nó sẽ đụng vào một app đang chạy: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }
}
