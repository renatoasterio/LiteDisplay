// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// A display override (`scale-resolutions`) that makes macOS offer HiDPI modes on a low-DPI panel.
/// Byte layout follows the widely used one-key-hidpi format: 8-byte entries are 1x resolutions,
/// 16-byte entries (width, height, 0x00000009, 0x00200000) are 2x "looks like" resolutions.
struct HiDPIOverrideProfile: Hashable, Sendable {
    static let overridesRoot = "/Library/Displays/Contents/Resources/Overrides"
    static let scaleResolutionsKey = "scale-resolutions"
    static let hiDPIFlagA: UInt32 = 0x0000_0009
    static let hiDPIFlagB: UInt32 = 0x0020_0000
    static let minimumWidth = 1280
    static let widthStep = 16

    let vendorID: UInt32
    let productID: UInt32
    let nativeSize: DisplaySize

    var vendorHex: String {
        String(vendorID, radix: 16)
    }

    var productHex: String {
        String(productID, radix: 16)
    }

    var directoryName: String {
        "DisplayVendorID-\(vendorHex)"
    }

    var fileName: String {
        "DisplayProductID-\(productHex)"
    }

    var installDirectory: String {
        "\(Self.overridesRoot)/\(directoryName)"
    }

    var installPath: String {
        "\(installDirectory)/\(fileName)"
    }

    /// Hex ids are the only user-independent input that reaches a privileged command, so they are validated.
    var hasValidIdentifiers: Bool {
        vendorID != 0 && productID != 0 && [vendorHex, productHex].allSatisfy { $0.range(
            of: "^[0-9a-f]{1,8}$",
            options: .regularExpression
        ) != nil }
    }

    /// "Looks like" sizes from the native width down to `minimumWidth`, keeping the panel's aspect ratio.
    var scaledSizes: [DisplaySize] {
        guard nativeSize.width >= Self.minimumWidth, nativeSize.height > 0 else { return [] }
        return stride(from: nativeSize.width, through: Self.minimumWidth, by: -Self.widthStep).map { width in
            let height = Int((Double(width) * Double(nativeSize.height) / Double(nativeSize.width)).rounded())
            return DisplaySize(width: width, height: height)
        }
    }

    /// 1x entries for every size, then 1x and 2x entries for every doubled size.
    var entries: [Data] {
        let sizes = scaledSizes
        return sizes.map(Self.encode1x) + sizes.map { Self.encode1x($0.doubled) } + sizes.map { Self.encodeHiDPI($0.doubled) }
    }

    func propertyList() -> [String: Any] {
        [
            "DisplayVendorID": Int(vendorID),
            "DisplayProductID": Int(productID),
            Self.scaleResolutionsKey: entries
        ]
    }

    func propertyListData() throws(LiteDisplayError) -> Data {
        do {
            return try PropertyListSerialization.data(fromPropertyList: propertyList(), format: .xml, options: 0)
        } catch {
            throw .storageFailed(error.localizedDescription)
        }
    }

    static func encode1x(_ size: DisplaySize) -> Data {
        bigEndian(UInt32(size.width)) + bigEndian(UInt32(size.height))
    }

    static func encodeHiDPI(_ pixelSize: DisplaySize) -> Data {
        bigEndian(UInt32(pixelSize.width)) + bigEndian(UInt32(pixelSize.height)) + bigEndian(hiDPIFlagA) + bigEndian(hiDPIFlagB)
    }

    /// Reads back an installed override; returns nil when the file is not a scale-resolutions override.
    static func decode(_ data: Data) -> (vendorID: Int, productID: Int, entries: [Data])? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let vendor = plist["DisplayVendorID"] as? Int,
              let product = plist["DisplayProductID"] as? Int,
              let entries = plist[scaleResolutionsKey] as? [Data] else { return nil }
        return (vendor, product, entries)
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
