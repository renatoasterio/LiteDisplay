// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import CoreGraphics

/// Lists the external displays with their mode tables and streams reconfiguration events.
@MainActor
final class DisplayEnumerator: DisplayProviding {
    private static let maxDisplays: UInt32 = 32
    private let observer = DisplayReconfigurationObserver()
    private let virtualDisplays: any VirtualDisplayControlling

    init(virtualDisplays: any VirtualDisplayControlling) {
        self.virtualDisplays = virtualDisplays
    }

    var changes: AsyncStream<DisplayChange> {
        observer.changes
    }

    func externalDisplays() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(Self.maxDisplays))
        guard CGGetOnlineDisplayList(Self.maxDisplays, &ids, &count) == .success else {
            Log.display.error("CGGetOnlineDisplayList failed")
            return []
        }
        let owned = virtualDisplays.ownedDisplayIDs
        return ids.prefix(Int(count))
            .filter {
                CGDisplayIsBuiltin($0) == 0 && !owned.contains($0) && CGDisplayVendorNumber($0) != DisplaySnapshot.virtualDisplayVendorID
            }
            .map { snapshot(for: $0, owned: owned) }
    }

    private func snapshot(for displayID: CGDirectDisplayID, owned: Set<UInt32>) -> DisplaySnapshot {
        let vendor = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        let mirrorSource = CGDisplayMirrorsDisplay(displayID)
        let size = CGDisplayScreenSize(displayID)
        let name = NSScreen.screen(for: displayID)?.localizedName
            ?? String(localized: "Monitor \(String(vendor, radix: 16)):\(String(product, radix: 16))")
        return DisplaySnapshot(
            id: displayID,
            persistentID: Self.persistentID(for: displayID, vendor: vendor, product: product, serial: serial),
            name: name,
            vendorID: vendor,
            productID: product,
            serialNumber: serial,
            physicalSize: PhysicalSize(widthMM: size.width, heightMM: size.height),
            isMain: CGDisplayIsMain(displayID) != 0,
            isBuiltIn: false,
            mirrorSourceID: mirrorSource == 0 ? nil : mirrorSource,
            isMirroringVirtualDisplay: owned.contains(mirrorSource),
            currentMode: DisplayModeCatalog.currentMode(of: displayID),
            modes: DisplayModeCatalog.usableModes(for: displayID)
        )
    }

    /// EDID-derived UUID (stable across ports and reboots), with a vendor-product-serial fallback.
    private static func persistentID(for displayID: CGDirectDisplayID, vendor: UInt32, product: UInt32, serial: UInt32) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "\(vendor)-\(product)-\(serial)"
    }
}
