import AppKit
import CoreAudio
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let manager = AudioDeviceManager.shared
    private var selectedDeviceUIDs: Set<String> = []
    private var individualSliders: [String: NSSlider] = [:]
    private var deviceChangeDebounceWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker.2.fill", accessibilityDescription: "DualAudio")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        recoverPreviousSessionIfNeeded()

        manager.startListeningForDeviceChanges { [weak self] in
            self?.scheduleDeviceListChangedCheck()
        }
    }

    private func scheduleDeviceListChangedCheck() {
        // Creating/destroying our own aggregate triggers this same notification,
        // and a real device can transiently report as unavailable mid-reconfiguration.
        // Debounce so a burst of notifications from our own changes settles before
        // we decide anything is actually gone.
        deviceChangeDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleDeviceListChanged()
        }
        deviceChangeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func recoverPreviousSessionIfNeeded() {
        var recoveredUIDs: Set<String>?

        if let currentID = manager.defaultOutputDeviceID(), manager.isOurAggregate(currentID) {
            let subUIDs = Set(manager.fullSubDeviceUIDs(of: currentID))
            let liveUIDs = Set(manager.listOutputDevices().map { $0.uid })
            recoveredUIDs = subUIDs.intersection(liveUIDs)
        }

        manager.destroyOrphanedAggregateDevices()

        if let recovered = recoveredUIDs, !recovered.isEmpty {
            selectedDeviceUIDs = recovered
            applySelection()
        } else {
            syncSelectionFromSystem()
        }

        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = selectedDeviceUIDs.count >= 2 ? "hifispeaker.2.fill" : "hifispeaker.fill"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "DualAudio")
    }

    private func handleDeviceListChanged() {
        let currentDevices = manager.listOutputDevices()
        let currentUIDs = Set(currentDevices.map { $0.uid })
        let missing = selectedDeviceUIDs.subtracting(currentUIDs)

        if !missing.isEmpty {
            selectedDeviceUIDs.subtract(missing)
            if selectedDeviceUIDs.isEmpty, let fallback = currentDevices.first {
                selectedDeviceUIDs = [fallback.uid]
            }
            applySelection()
        }

        refreshMenuNow()
    }

    private func refreshMenuNow() {
        guard let menu = statusItem.menu else { return }
        menuNeedsUpdate(menu)
    }

    private func syncSelectionFromSystem() {
        guard let currentID = manager.defaultOutputDeviceID(), currentID != manager.currentAggregateID else { return }
        if let uid = manager.uid(of: currentID) {
            selectedDeviceUIDs = [uid]
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let devices = manager.listOutputDevices()

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(toggleDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            item.state = selectedDeviceUIDs.contains(device.uid) ? .on : .off
            menu.addItem(item)
        }

        let activeDevices = devices.filter { selectedDeviceUIDs.contains($0.uid) }
        if activeDevices.count >= 2 {
            menu.addItem(NSMenuItem.separator())

            let volumes = activeDevices.compactMap { manager.getVolume($0.id) }
            let averageVolume = volumes.isEmpty ? 1.0 : volumes.reduce(0, +) / Float(volumes.count)

            let masterItem = NSMenuItem()
            masterItem.view = SliderMenuItemView(
                title: "Volume (all)",
                value: averageVolume,
                tag: Self.masterVolumeTag,
                target: self,
                action: #selector(volumeSliderChanged(_:)))
            menu.addItem(masterItem)

            individualSliders.removeAll()
            for device in activeDevices {
                let item = NSMenuItem()
                let sliderView = SliderMenuItemView(
                    title: device.name,
                    value: manager.getVolume(device.id) ?? 1.0,
                    tag: Int(device.id),
                    target: self,
                    action: #selector(volumeSliderChanged(_:)))
                item.view = sliderView
                individualSliders[device.uid] = sliderView.slider
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchAtLoginItem)

        let quitItem = NSMenuItem(title: "Quit DualAudio", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("[DualAudio] Launch-at-login toggle failed: \(error)")
        }
    }

    private static let masterVolumeTag = -1

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let value = sender.floatValue
        if sender.tag == Self.masterVolumeTag {
            let devices = manager.listOutputDevices().filter { selectedDeviceUIDs.contains($0.uid) }
            for device in devices {
                manager.setVolume(device.id, scalar: value)
                individualSliders[device.uid]?.floatValue = value
            }
        } else {
            manager.setVolume(AudioDeviceID(sender.tag), scalar: value)
        }
    }

    @objc private func toggleDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? OutputDevice else { return }

        if selectedDeviceUIDs.contains(device.uid) {
            if selectedDeviceUIDs.count > 1 {
                selectedDeviceUIDs.remove(device.uid)
            }
        } else {
            selectedDeviceUIDs.insert(device.uid)
            manager.setMute(device.id, muted: false)
        }

        applySelection()
    }

    private func applySelection() {
        updateStatusIcon()
        let devices = manager.listOutputDevices().filter { selectedDeviceUIDs.contains($0.uid) }

        if devices.count <= 1 {
            // Point default output at the already-live single device first, then
            // tear down the old aggregate after a beat — avoids a gap where macOS
            // would otherwise fall back to some other default (audible blip), and
            // avoids the destroy's device-list churn re-resolving default output
            // to the wrong device before the new selection has settled.
            if let single = devices.first {
                manager.setDefaultOutputDevice(single.id)
            }
            let aggregateToRetire = manager.currentAggregateID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                // Only destroy if nothing newer has replaced it in the meantime
                // (e.g. the user switched back to a multi-device combo before
                // this fired) — otherwise this stale cleanup would tear down a
                // brand new, currently-in-use aggregate.
                guard self.manager.currentAggregateID == aggregateToRetire else { return }
                self.manager.destroyCurrentAggregateDevice()
            }
            return
        }

        manager.destroyCurrentAggregateDevice()

        let activate = { [weak self] in
            guard let self else { return }
            let currentDevices = self.manager.listOutputDevices().filter { self.selectedDeviceUIDs.contains($0.uid) }
            if let aggregateID = self.manager.createMultiOutputDevice(devices: currentDevices) {
                self.manager.setDefaultOutputDevice(aggregateID)
                self.verifyAggregateHealth(expectedUIDs: Set(currentDevices.map { $0.uid }), attempt: 1)
            }
        }

        // Give a torn-down Bluetooth sub-device stream time to fully release before
        // it's asked to re-attach to a freshly created aggregate. Measured from the
        // last actual destroy (which may have happened in an earlier, unrelated call,
        // e.g. a quick dual -> single -> dual toggle), not just this invocation.
        let cooldown: TimeInterval = 0.3
        let elapsedSinceDestroy = manager.lastAggregateDestroyTime.map { Date().timeIntervalSince($0) } ?? .infinity
        let remainingDelay = max(0, cooldown - elapsedSinceDestroy)

        if remainingDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay, execute: activate)
        } else {
            activate()
        }
    }

    private func verifyAggregateHealth(expectedUIDs: Set<String>, attempt: Int) {
        guard attempt <= 2 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            // Bail if the user has since changed the selection — nothing to heal.
            guard self.selectedDeviceUIDs == expectedUIDs else { return }

            let currentDevices = self.manager.listOutputDevices().filter { expectedUIDs.contains($0.uid) }
            let allRunning = currentDevices.count == expectedUIDs.count
                && currentDevices.allSatisfy { self.manager.isRunning($0.id) }

            guard !allRunning else { return }

            // One or more Bluetooth sub-devices never fully attached to the
            // aggregate — rebuild it once, which reliably clears this up.
            self.manager.destroyCurrentAggregateDevice()
            if let aggregateID = self.manager.createMultiOutputDevice(devices: currentDevices) {
                self.manager.setDefaultOutputDevice(aggregateID)
            }
            self.verifyAggregateHealth(expectedUIDs: expectedUIDs, attempt: attempt + 1)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
