import XCTest
@testable import HirundoCore

final class FileIdentityTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-identity-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSameUnchangedFileHasEqualIdentity() throws {
        let file = tempDir.appendingPathComponent("a.bin")
        try Data("bytes".utf8).write(to: file)

        let first = try FileIdentity(ofItemAtPath: file.path)
        let second = try FileIdentity(ofItemAtPath: file.path)
        XCTAssertEqual(first, second)
    }

    func testAppendingBytesChangesIdentity() throws {
        let file = tempDir.appendingPathComponent("a.bin")
        try Data("bytes".utf8).write(to: file)
        let before = try FileIdentity(ofItemAtPath: file.path)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("more".utf8))
        try handle.close()

        XCTAssertNotEqual(before, try FileIdentity(ofItemAtPath: file.path), "サイズが変わったのに同一と判定された")
    }

    /// 同じ名前・同じサイズでも、別のファイルに置き換えられたら別物。inode が変わる。
    func testReplacingTheFileWithSameSizedContentChangesIdentity() throws {
        let file = tempDir.appendingPathComponent("a.bin")
        try Data("bytes".utf8).write(to: file)
        let before = try FileIdentity(ofItemAtPath: file.path)

        try FileManager.default.removeItem(at: file)
        try Data("BYTES".utf8).write(to: file)

        XCTAssertNotEqual(before, try FileIdentity(ofItemAtPath: file.path), "別ファイルに差し替えられたのに同一と判定された")
    }

    /// サイズも inode も変わらない上書きは、更新時刻で検出する。
    func testInPlaceOverwriteOfSameSizeChangesIdentity() throws {
        let file = tempDir.appendingPathComponent("a.bin")
        try Data("bytes".utf8).write(to: file)
        let before = try FileIdentity(ofItemAtPath: file.path)

        // 更新時刻の分解能（APFS はナノ秒）より確実に離す。
        Thread.sleep(forTimeInterval: 0.02)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data("BYTES".utf8))
        try handle.close()

        XCTAssertNotEqual(before, try FileIdentity(ofItemAtPath: file.path), "同サイズの上書きが検出されていない")
    }

    func testMissingFileThrows() {
        XCTAssertThrowsError(try FileIdentity(ofItemAtPath: tempDir.appendingPathComponent("missing").path))
    }
}
