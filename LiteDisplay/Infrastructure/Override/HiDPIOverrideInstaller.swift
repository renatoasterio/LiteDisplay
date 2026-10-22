// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Writes the override plist to a private temporary file and copies it into /Library/Displays as root, then
/// reads it back to prove the installed file is byte-for-byte what was generated.
struct HiDPIOverrideInstaller: OverrideInstalling {
    let runner: any PrivilegedExecuting

    func isInstalled(_ profile: HiDPIOverrideProfile) -> Bool {
        FileManager.default.fileExists(atPath: profile.installPath)
    }

    func install(_ profile: HiDPIOverrideProfile) async throws(LiteDisplayError) {
        guard profile.hasValidIdentifiers else { throw .invalidIdentifier }
        let data = try profile.propertyListData()
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiteDisplay-override-\(UUID().uuidString)", isDirectory: true)
        let stagedFile = stagingDirectory.appendingPathComponent(profile.fileName)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        try stage(data, at: stagedFile, in: stagingDirectory)

        let command = Self.installCommand(for: profile, stagedPath: stagedFile.path)
        let prompt = String(localized: "O LiteDisplay precisa de permissão de administrador para instalar o perfil HiDPI do monitor.")
        try await runner.run(command, prompt: prompt)
        try verify(profile)
        Log.override.info("Installed override at \(profile.installPath, privacy: .public)")
    }

    /// mkdir, back up any previous file, copy, then fix ownership and mode. Every path is single-quoted.
    static func installCommand(for profile: HiDPIOverrideProfile, stagedPath: String) -> String {
        let directory = PrivilegedRunner.shellQuoted(profile.installDirectory)
        let destination = PrivilegedRunner.shellQuoted(profile.installPath)
        let backup = PrivilegedRunner.shellQuoted(profile.installPath + ".bak")
        let source = PrivilegedRunner.shellQuoted(stagedPath)
        return [
            "/bin/mkdir -p \(directory)",
            "if [ -f \(destination) ]; then /bin/cp \(destination) \(backup); fi",
            "/bin/cp \(source) \(destination)",
            "/usr/sbin/chown root:wheel \(destination)",
            "/bin/chmod 644 \(destination)"
        ].joined(separator: " && ")
    }

    private func stage(_ data: Data, at file: URL, in directory: URL) throws(LiteDisplayError) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        } catch {
            throw .storageFailed(error.localizedDescription)
        }
    }

    private func verify(_ profile: HiDPIOverrideProfile) throws(LiteDisplayError) {
        guard let installed = FileManager.default.contents(atPath: profile.installPath) else {
            throw .overrideVerificationFailed(String(localized: "arquivo ausente"))
        }
        guard let decoded = HiDPIOverrideProfile.decode(installed) else {
            throw .overrideVerificationFailed(String(localized: "formato inválido"))
        }
        guard decoded.vendorID == Int(profile.vendorID), decoded.productID == Int(profile.productID) else {
            throw .overrideVerificationFailed(String(localized: "identificadores diferentes"))
        }
        guard Set(decoded.entries) == Set(profile.entries) else {
            throw .overrideVerificationFailed(String(localized: "resoluções diferentes"))
        }
    }
}
