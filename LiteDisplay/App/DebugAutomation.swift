// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

#if DEBUG
import AppKit
import Foundation

/// Debug-only launch arguments that drive the real services without the UI, so the full stack can be verified
/// from the command line:
///
///     LiteDisplay --litedisplay-method hiDPI|standard|virtualDisplay [--litedisplay-size 1600x900]
///                 [--litedisplay-rate 120] [--litedisplay-quit-after 5]
///
/// Results are logged under the `app` category and printed to stderr. Never compiled into Release.
@MainActor
enum DebugAutomation {
    struct Request {
        let method: SharpnessMethod
        let size: DisplaySize?
        let refreshRate: Double?
        let quitAfter: Double?
    }

    static func request(from arguments: [String] = CommandLine.arguments) -> Request? {
        guard let methodValue = value(for: "--litedisplay-method", in: arguments),
              let method = SharpnessMethod(rawValue: methodValue) else { return nil }
        let size = value(for: "--litedisplay-size", in: arguments).flatMap { raw -> DisplaySize? in
            let parts = raw.split(separator: "x").compactMap { Int($0) }
            return parts.count == 2 ? DisplaySize(width: parts[0], height: parts[1]) : nil
        }
        let rate = value(for: "--litedisplay-rate", in: arguments).flatMap(Double.init)
        let quitAfter = value(for: "--litedisplay-quit-after", in: arguments).flatMap(Double.init)
        return Request(method: method, size: size, refreshRate: rate, quitAfter: quitAfter)
    }

    static func run(_ request: Request, container: AppContainer) async {
        container.monitors.refresh()
        guard let display = container.monitors.displays.first else {
            report("no external display")
            return finish(after: request.quitAfter)
        }
        report("before: \(display.name) \(display.currentMode?.summary ?? "-") method=\(display.activeMethod.rawValue)")
        if request.size != nil || request.refreshRate != nil {
            if let size = request.size {
                await container.monitors.setSize(size, for: display)
            }
            if let rate = request.refreshRate, let refreshed = container.monitors.display(withID: display.id) {
                await container.monitors.setRefreshRate(rate, for: refreshed)
            }
        } else {
            await container.monitors.setMethod(request.method, for: display)
        }
        let after = container.monitors.display(withID: display.id)
        let mode = after?.currentMode?.summary ?? "-"
        let method = after?.activeMethod.rawValue ?? "-"
        report("after: \(mode) method=\(method) virtual=\(after?.isMirroringVirtualDisplay ?? false)")
        if let error = container.monitors.error {
            report("error: \(error.localizedDescription) — \(error.recoverySuggestion ?? "")")
        }
        finish(after: request.quitAfter)
    }

    private static func finish(after seconds: Double?) {
        guard let seconds else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            NSApp.terminate(nil)
        }
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func report(_ message: String) {
        Log.app.notice("[automation] \(message, privacy: .public)")
        FileHandle.standardError.write(Data("[automation] \(message)\n".utf8))
    }
}
#endif
