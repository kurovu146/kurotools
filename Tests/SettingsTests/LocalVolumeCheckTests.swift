import XCTest
@testable import Settings

final class LocalVolumeCheckTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func verdict(_ path: String, local: Bool? = true) -> LocationVerdict {
        LocalVolumeCheck.verdict(
            for: URL(fileURLWithPath: path), home: home, isLocalVolume: { _ in local })
    }

    // Cây thư mục thật cho test symlink — mọi test khác ở trên dùng đường dẫn
    // chuỗi thuần không tồn tại trên đĩa, nên `resolvingSymlinksInPath()` (chạy
    // trên realpath(3)) là no-op im lặng với chúng và không kiểm được cơ chế
    // gỡ symlink. Test này dựng file thật để cơ chế đó thực sự chạy.
    private var tempRoot: URL!
    private var fakeHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LocalVolumeCheckTests-\(UUID().uuidString)")
        // NSTemporaryDirectory() bản thân thường nằm dưới /var, vốn là symlink
        // tới /private/var — resolve MỘT LẦN ở đây rồi dùng giá trị đã resolve
        // làm `home`, kẻo phép so tiền tố-home fail vì lý do không liên quan
        // tới thứ đang test.
        fakeHome = tempRoot.appendingPathComponent("home").resolvingSymlinksInPath()
        let cloudFolder = fakeHome
            .appendingPathComponent("Library/CloudStorage/Dropbox/data")
        try FileManager.default.createDirectory(
            at: cloudFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        fakeHome = nil
        try super.tearDownWithError()
    }

    func testAnOrdinaryLocalFolderIsAllowed() {
        XCTAssertEqual(verdict("/Users/tester/Documents/kuro"), .ok)
    }

    func testANetworkVolumeIsRejected() {
        XCTAssertEqual(verdict("/Volumes/nas/kuro", local: false), .notLocalVolume)
    }

    func testAVolumeWhoseLocalityIsUnknownIsRejected() {
        // Không đọc được thuộc tính thì coi như không đạt: đoán "chắc là local"
        // đúng chỗ này nghĩa là đặt db lên ổ mạng.
        XCTAssertEqual(verdict("/Volumes/mystery/kuro", local: nil), .notLocalVolume)
    }

    func testICloudDriveIsRejectedEvenThoughItIsOnALocalVolume() {
        XCTAssertEqual(
            verdict("/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/kuro"),
            .cloudSynced("iCloud Drive"))
    }

    func testCloudStorageProvidersAreRejected() {
        XCTAssertEqual(
            verdict("/Users/tester/Library/CloudStorage/Dropbox/kuro"),
            .cloudSynced("Dropbox"))
        XCTAssertEqual(
            verdict("/Users/tester/Library/CloudStorage/GoogleDrive-a@b.com/kuro"),
            .cloudSynced("Google Drive"))
        XCTAssertEqual(
            verdict("/Users/tester/Library/CloudStorage/OneDrive-Personal/kuro"),
            .cloudSynced("OneDrive"))
    }

    func testALegacyDropboxFolderInHomeIsRejected() {
        XCTAssertEqual(verdict("/Users/tester/Dropbox/kuro"), .cloudSynced("Dropbox"))
    }

    func testAFolderMerelyNamedLikeACloudFolderElsewhereIsAllowed() {
        // "Dropbox" chỉ bị chặn khi nằm đúng chỗ, không phải mọi nơi có chữ đó.
        XCTAssertEqual(verdict("/Users/tester/Projects/Dropbox-clone"), .ok)
    }

    func testASymlinkPointingIntoDropboxIsRejectedEvenViaAnUnrelatedPath() throws {
        let cloudFolder = fakeHome
            .appendingPathComponent("Library/CloudStorage/Dropbox/data")
        let shortcut = fakeHome.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(
            at: shortcut, withDestinationURL: cloudFolder)

        XCTAssertEqual(
            LocalVolumeCheck.verdict(for: shortcut, home: fakeHome, isLocalVolume: { _ in true }),
            .cloudSynced("Dropbox"))
    }
}
