import Testing
@testable import pockterm

@Test func kindFromMode() {
    #expect(RemoteFile.kind(fromMode: 0o040755) == .directory)
    #expect(RemoteFile.kind(fromMode: 0o100644) == .regular)
    #expect(RemoteFile.kind(fromMode: 0o120777) == .symlink)
    #expect(RemoteFile.kind(fromMode: 0o010000) == .other)
}

@Test func permissionString() {
    #expect(RemoteFile.permissionString(0o755) == "rwxr-xr-x")
    #expect(RemoteFile.permissionString(0o640) == "rw-r-----")
    #expect(RemoteFile.permissionString(0o000) == "---------")
    // Only the low 9 permission bits matter, even with file-type bits set.
    #expect(RemoteFile.permissionString(0o100644) == "rw-r--r--")
}

@Test func joinPath() {
    #expect(RemoteFile.joinPath("/a", "b") == "/a/b")
    #expect(RemoteFile.joinPath("/", "b") == "/b")
    #expect(RemoteFile.joinPath("/a/", "b") == "/a/b")
}
