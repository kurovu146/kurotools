import XCTest
@testable import Settings

final class LocalVolumeCheckTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func verdict(_ path: String, local: Bool? = true) -> LocationVerdict {
        LocalVolumeCheck.verdict(
            for: URL(fileURLWithPath: path), home: home, isLocalVolume: { _ in local })
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
}
