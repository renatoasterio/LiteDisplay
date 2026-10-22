// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Testing
@testable import LiteDisplay

@Suite("HiDPI override profile")
struct HiDPIOverrideProfileTests {
    let profile = HiDPIOverrideProfile(vendorID: 0x472, productID: 0x746, nativeSize: DisplaySize(width: 1920, height: 1080))

    @Test("1x entries are two big-endian words")
    func encodes1x() {
        #expect(HiDPIOverrideProfile.encode1x(DisplaySize(width: 1440, height: 810)) == Data([0, 0, 0x05, 0xA0, 0, 0, 0x03, 0x2A]))
    }

    @Test("HiDPI entries carry the 0x00000009 0x00200000 suffix")
    func encodesHiDPI() {
        let expected = Data([0, 0, 0x0D, 0xA0, 0, 0, 0x07, 0xAA, 0, 0, 0, 0x09, 0, 0x20, 0, 0])
        #expect(HiDPIOverrideProfile.encodeHiDPI(DisplaySize(width: 3488, height: 1962)) == expected)
    }

    @Test("A 1080p panel yields 41 sizes and 123 entries")
    func entryCount() {
        #expect(profile.scaledSizes.count == 41)
        #expect(profile.scaledSizes.first == DisplaySize(width: 1920, height: 1080))
        #expect(profile.scaledSizes.last == DisplaySize(width: 1280, height: 720))
        #expect(profile.entries.count == 123)
        #expect(profile.entries.filter { $0.count == 16 }.count == 41)
    }

    @Test("Paths use lowercase hex without padding")
    func paths() {
        #expect(profile.installPath == "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-472/DisplayProductID-746")
        #expect(profile.hasValidIdentifiers)
        #expect(!HiDPIOverrideProfile(vendorID: 0, productID: 1, nativeSize: profile.nativeSize).hasValidIdentifiers)
    }

    @Test("The plist round-trips")
    func roundTrip() throws {
        let data = try profile.propertyListData()
        let decoded = try #require(HiDPIOverrideProfile.decode(data))
        #expect(decoded.vendorID == 1138)
        #expect(decoded.productID == 1862)
        #expect(decoded.entries == profile.entries)
    }

    @Test("Matches the override installed on this Mac when present")
    func matchesInstalledOverride() throws {
        guard let data = FileManager.default.contents(atPath: profile.installPath) else { return }
        let installed = try #require(HiDPIOverrideProfile.decode(data))
        #expect(installed.vendorID == 1138)
        #expect(installed.productID == 1862)
        #expect(Set(installed.entries) == Set(profile.entries))
    }

    @Test("The install command quotes every path and fixes ownership")
    func installCommand() {
        let command = HiDPIOverrideInstaller.installCommand(for: profile, stagedPath: "/tmp/it's here/DisplayProductID-746")
        #expect(command.contains("/bin/mkdir -p '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-472'"))
        #expect(command.contains("'/tmp/it'\\''s here/DisplayProductID-746'"))
        #expect(command.contains("/usr/sbin/chown root:wheel"))
        #expect(command
            .hasSuffix("/bin/chmod 644 '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-472/DisplayProductID-746'"))
    }

    @Test("AppleScript literals escape quotes and backslashes")
    func appleScriptLiteral() {
        #expect(PrivilegedRunner.appleScriptLiteral(#"say "hi" \ bye"#) == #""say \"hi\" \\ bye""#)
        #expect(PrivilegedRunner.shellQuoted("a'b") == #"'a'\''b'"#)
    }

    @Test("Installer stages, runs the command and verifies")
    func installerFlow() async throws {
        let executor = FakePrivilegedExecutor()
        let installer = HiDPIOverrideInstaller(runner: executor)
        let unknown = HiDPIOverrideProfile(vendorID: 0xABCD, productID: 0x1234, nativeSize: DisplaySize(width: 1920, height: 1080))
        await #expect(throws: LiteDisplayError.self) {
            // The fake runs nothing, so verification fails: the installer must not report success.
            try await installer.install(unknown)
        }
        #expect(executor.commands.count == 1)
        #expect(executor.commands[0].contains("DisplayVendorID-abcd/DisplayProductID-1234"))
    }
}
