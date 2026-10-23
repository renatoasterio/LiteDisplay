// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// State for the monitor screens and the menu: the connected displays, the operation in flight and the last outcome.
@MainActor
@Observable
final class MonitorsViewModel {
    private static let refreshDebounce: Duration = .milliseconds(1500)

    private(set) var displays: [DisplaySnapshot] = []
    private(set) var isApplying = false
    var error: LiteDisplayError?
    var notice: String?
    let isVirtualDisplayAvailable: Bool

    @ObservationIgnored private let provider: any DisplayProviding
    @ObservationIgnored private let virtualDisplays: any VirtualDisplayControlling
    @ObservationIgnored private let sharpness: SetSharpnessUseCase
    @ObservationIgnored private let resolution: ChangeResolutionUseCase
    @ObservationIgnored private let overrideInstaller: EnableHiDPIOverrideUseCase
    @ObservationIgnored private let reapply: ReapplyOnConnectUseCase
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var relaunch: Task<Void, Never>?
    /// Restarts the app; set by the composition root. A released virtual display only disappears with the process.
    @ObservationIgnored var relaunchHandler: (@MainActor () -> Void)?
    /// Displays whose override was installed in this session and still need a reconnection.
    @ObservationIgnored private var pendingOverrides: Set<String> = []

    init(
        provider: any DisplayProviding,
        virtualDisplays: any VirtualDisplayControlling,
        sharpness: SetSharpnessUseCase,
        resolution: ChangeResolutionUseCase,
        overrideInstaller: EnableHiDPIOverrideUseCase,
        reapply: ReapplyOnConnectUseCase
    ) {
        self.provider = provider
        self.virtualDisplays = virtualDisplays
        self.sharpness = sharpness
        self.resolution = resolution
        self.overrideInstaller = overrideInstaller
        self.reapply = reapply
        isVirtualDisplayAvailable = virtualDisplays.isAvailable
    }

    // MARK: - Lifecycle

    func start() {
        refresh()
        observation?.cancel()
        observation = Task { [weak self] in
            guard let stream = self?.provider.changes else { return }
            for await change in stream {
                guard let self, !Task.isCancelled else { return }
                handle(change)
            }
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        relaunch?.cancel()
        relaunch = nil
    }

    /// After a virtual display was turned off, the app restarts itself so the window server drops the display.
    func relaunchIfVirtualDisplayLingers() {
        guard !virtualDisplays.lingeringDisplayIDs.isEmpty, relaunch == nil else { return }
        notice = String(localized: "Tela virtual desligada. O LiteDisplay vai reabrir em instantes para liberá-la.")
        relaunch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            relaunchHandler?()
        }
    }

    func refresh() {
        displays = provider.externalDisplays()
        pendingOverrides = pendingOverrides.filter { id in displays.first { $0.persistentID == id }?.hasUsableHiDPI != true }
    }

    func display(withID id: UInt32) -> DisplaySnapshot? {
        displays.first { $0.id == id }
    }

    // MARK: - Actions

    func setMethod(_ method: SharpnessMethod, for display: DisplaySnapshot) async {
        await perform { () async throws(LiteDisplayError) in try await sharpness.execute(.init(display: display, method: method)) }
    }

    func setSize(_ size: DisplaySize, for display: DisplaySnapshot) async {
        await perform { () async throws(LiteDisplayError) in try await resolution.execute(display: display, size: size) }
    }

    func setRefreshRate(_ rate: Double, for display: DisplaySnapshot) async {
        await perform { () async throws(LiteDisplayError) in try await resolution.execute(display: display, refreshRate: rate) }
    }

    func apply(_ mode: DisplayMode, to display: DisplaySnapshot) async {
        await perform { () async throws(LiteDisplayError) in try await resolution.execute(display: display, mode: mode) }
    }

    /// Quick toggle used by the menu: sharp on → HiDPI when the display offers it, else the virtual display.
    func setSharp(_ sharp: Bool, for display: DisplaySnapshot) async {
        let method: SharpnessMethod = sharp ? (display.hasUsableHiDPI ? .hiDPI : .virtualDisplay) : .standard
        await setMethod(method, for: display)
    }

    func installOverride(for display: DisplaySnapshot) async {
        await perform { () async throws(LiteDisplayError) in
            _ = try await overrideInstaller.execute(for: display)
            pendingOverrides.insert(display.persistentID)
            notice = String(localized: "Perfil HiDPI instalado. Reconecte o monitor (ou reinicie o Mac) para ver as novas resoluções.")
        }
    }

    func isOverridePending(for display: DisplaySnapshot) -> Bool {
        pendingOverrides.contains(display.persistentID)
    }

    func dismissMessages() {
        error = nil
        notice = nil
    }

    // MARK: - Derived data

    func curatedSizes(for display: DisplaySnapshot) -> [CuratedSize] {
        let active = display.activeMethod == .hiDPI ? display.currentMode?.size : nil
        return ModeSelection.curatedSizes(in: display.modes, including: active)
    }

    func refreshRates(for display: DisplaySnapshot) -> [Double] {
        guard let current = display.currentMode else { return [] }
        return ModeSelection.refreshRates(in: display.modes, size: current.size, hiDPI: current.isHiDPI)
    }

    // MARK: - Private

    private func perform(_ work: () async throws(LiteDisplayError) -> Void) async {
        guard !isApplying else { return }
        isApplying = true
        error = nil
        notice = nil
        defer { isApplying = false }
        do {
            try await work()
        } catch {
            self.error = error
            Log.ui.error("Display action failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
        relaunchIfVirtualDisplayLingers()
    }

    private func handle(_ change: DisplayChange) {
        // Our own transactions also fire reconfiguration callbacks; the refresh after `perform` covers them.
        guard !isApplying else { return }
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDebounce)
            guard let self, !Task.isCancelled else { return }
            refresh()
            if case let .added(displayID) = change {
                await reapplyIfNeeded(displayID: displayID)
            }
        }
    }

    private func reapplyIfNeeded(displayID: UInt32) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            if try await reapply.execute(displayID: displayID) {
                Log.ui.info("Restored configuration on display \(displayID)")
            }
        } catch {
            Log.ui.error("Could not restore display \(displayID): \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }
}
