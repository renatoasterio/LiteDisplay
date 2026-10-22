#!/usr/bin/env swift
// LiteDisplay diagnostics: prints every online display and all of its modes (including HiDPI duplicates).
// Usage: swift scripts/dump-modes.swift [--all]   (--all also lists modes not usable for the desktop GUI)
import AppKit
import CoreGraphics
import Foundation

let listAll = CommandLine.arguments.contains("--all")
var count: UInt32 = 0
var ids = [CGDirectDisplayID](repeating: 0, count: 16)
CGGetOnlineDisplayList(16, &ids, &count)

func hex(_ value: UInt32) -> String { String(value, radix: 16) }

for id in ids.prefix(Int(count)) {
    let screen = NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
    }
    let name = screen?.localizedName ?? "?"
    let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "-"
    let mm = CGDisplayScreenSize(id)
    print("Display \(id) '\(name)'")
    print("  builtin=\(CGDisplayIsBuiltin(id) != 0) main=\(CGDisplayIsMain(id) != 0) mirrorOf=\(CGDisplayMirrorsDisplay(id)) inMirrorSet=\(CGDisplayIsInMirrorSet(id) != 0)")
    print("  vendor=0x\(hex(CGDisplayVendorNumber(id))) model=0x\(hex(CGDisplayModelNumber(id))) serial=\(CGDisplaySerialNumber(id)) uuid=\(uuid)")
    print("  size=\(Int(mm.width))x\(Int(mm.height))mm backingScale=\(screen?.backingScaleFactor ?? 0)")
    let current = CGDisplayCopyDisplayMode(id)
    if let current {
        print("  CURRENT: \(current.width)x\(current.height) px=\(current.pixelWidth)x\(current.pixelHeight) @\(current.refreshRate)Hz flags=0x\(hex(current.ioFlags)) id=\(current.ioDisplayModeID)")
    }
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
    let usable = modes.filter { $0.isUsableForDesktopGUI() }
    print("  modes: \(modes.count) total, \(usable.count) usable, \(usable.filter { $0.pixelWidth == $0.width * 2 }.count) HiDPI")
    for mode in (listAll ? modes : usable).sorted(by: { ($0.width, $0.height, $0.refreshRate) > ($1.width, $1.height, $1.refreshRate) }) {
        let scale = mode.pixelWidth == mode.width * 2 ? "2x" : "1x"
        let marker = mode.ioDisplayModeID == current?.ioDisplayModeID ? " <== current" : ""
        let usableMark = mode.isUsableForDesktopGUI() ? "" : " (not usable)"
        print("    \(mode.width)x\(mode.height) px=\(mode.pixelWidth)x\(mode.pixelHeight) @\(Int(mode.refreshRate.rounded()))Hz \(scale) flags=0x\(hex(mode.ioFlags)) id=\(mode.ioDisplayModeID)\(usableMark)\(marker)")
    }
}
