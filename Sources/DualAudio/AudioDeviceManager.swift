import Foundation
import CoreAudio
import AudioToolbox

struct OutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    private let aggregateUIDPrefix = "com.dualaudio.multiout."
    private(set) var currentAggregateID: AudioDeviceID?
    private(set) var lastAggregateDestroyTime: Date?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?

    func startListeningForDeviceChanges(_ handler: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                handler()
            }
        }
        deviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    func listOutputDevices() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard hasOutputStreams(deviceID), let uid = deviceUID(deviceID) else { return nil }
            if uid.hasPrefix(aggregateUIDPrefix) { return nil }
            let name = deviceName(deviceID) ?? "Unknown Device"
            return OutputDevice(id: deviceID, uid: uid, name: name)
        }
    }

    func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        return status == noErr ? deviceID : nil
    }

    @discardableResult
    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var mutableID = deviceID
        let status1 = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID)

        var systemAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var mutableID2 = deviceID
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &systemAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID2)

        return status1 == noErr
    }

    func createMultiOutputDevice(devices: [OutputDevice]) -> AudioDeviceID? {
        guard devices.count >= 2 else { return nil }

        let uid = aggregateUIDPrefix + UUID().uuidString
        var subDeviceList: [[String: Any]] = []
        for device in devices {
            let subDict: [String: Any] = [
                kAudioSubDeviceUIDKey as String: device.uid,
                kAudioSubDeviceDriftCompensationKey as String: 1
            ]
            subDeviceList.append(subDict)
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "DualAudio Output",
            kAudioAggregateDeviceUIDKey as String: uid,
            kAudioAggregateDeviceIsPrivateKey as String: 0,
            kAudioAggregateDeviceIsStackedKey as String: 1,
            kAudioAggregateDeviceMainSubDeviceKey as String: devices[0].uid,
            kAudioAggregateDeviceSubDeviceListKey as String: subDeviceList
        ]

        var aggregateID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else {
            return nil
        }
        currentAggregateID = aggregateID
        return aggregateID
    }

    @discardableResult
    func setVolume(_ deviceID: AudioDeviceID, scalar: Float32) -> Bool {
        let clamped = max(0, min(1, scalar))
        var mainAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        if AudioObjectHasProperty(deviceID, &mainAddress) {
            var value = clamped
            let status = AudioObjectSetPropertyData(deviceID, &mainAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            return status == noErr
        }

        var appliedAny = false
        for channel: UInt32 in [1, 2] {
            var channelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel)
            if AudioObjectHasProperty(deviceID, &channelAddress) {
                var value = clamped
                let status = AudioObjectSetPropertyData(deviceID, &channelAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
                appliedAny = appliedAny || (status == noErr)
            }
        }
        return appliedAny
    }

    func getVolume(_ deviceID: AudioDeviceID) -> Float32? {
        var mainAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        if AudioObjectHasProperty(deviceID, &mainAddress) {
            let status = AudioObjectGetPropertyData(deviceID, &mainAddress, 0, nil, &dataSize, &value)
            return status == noErr ? value : nil
        }

        var channelAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1)
        if AudioObjectHasProperty(deviceID, &channelAddress) {
            let status = AudioObjectGetPropertyData(deviceID, &channelAddress, 0, nil, &dataSize, &value)
            return status == noErr ? value : nil
        }
        return nil
    }

    func uid(of deviceID: AudioDeviceID) -> String? {
        deviceUID(deviceID)
    }

    func isRunning(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        return status == noErr && value != 0
    }

    func isOurAggregate(_ deviceID: AudioDeviceID) -> Bool {
        guard let uid = deviceUID(deviceID) else { return false }
        return uid.hasPrefix(aggregateUIDPrefix)
    }

    func fullSubDeviceUIDs(of aggregateID: AudioDeviceID) -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregateID, &address, 0, nil, &dataSize) == noErr else { return [] }
        var array: CFArray?
        let status = withUnsafeMutablePointer(to: &array) { ptr -> OSStatus in
            AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr, let uids = array as? [String] else { return [] }
        return uids
    }

    @discardableResult
    func setMute(_ deviceID: AudioDeviceID, muted: Bool) -> Bool {
        let value: UInt32 = muted ? 1 : 0
        var mainAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        if AudioObjectHasProperty(deviceID, &mainAddress) {
            var mutable = value
            let status = AudioObjectSetPropertyData(deviceID, &mainAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mutable)
            return status == noErr
        }

        var appliedAny = false
        for channel: UInt32 in [1, 2] {
            var channelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel)
            if AudioObjectHasProperty(deviceID, &channelAddress) {
                var mutable = value
                let status = AudioObjectSetPropertyData(deviceID, &channelAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mutable)
                appliedAny = appliedAny || (status == noErr)
            }
        }
        return appliedAny
    }

    func destroyCurrentAggregateDevice() {
        guard let aggregateID = currentAggregateID else { return }
        AudioHardwareDestroyAggregateDevice(aggregateID)
        currentAggregateID = nil
        lastAggregateDestroyTime = Date()
    }

    /// Removes any of our aggregate devices left behind by a previous crash or force-quit.
    func destroyOrphanedAggregateDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else { return }

        for deviceID in deviceIDs {
            guard let uid = deviceUID(deviceID), uid.hasPrefix(aggregateUIDPrefix) else { continue }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
    }

    private func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawPtr) == noErr else {
            return false
        }
        let bufferList = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { ptr -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr else { return nil }
        return uid as String
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr else { return nil }
        return name as String
    }
}
