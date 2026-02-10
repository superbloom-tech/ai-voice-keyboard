import CoreAudio
import Foundation

enum DefaultAudioInputDevice {
  static func name() -> String? {
    guard let id = deviceID() else { return nil }
    return deviceName(deviceID: id)
  }

  static func nominalSampleRate() -> Double? {
    guard let id = deviceID() else { return nil }
    return deviceNominalSampleRate(deviceID: id)
  }

  private static func deviceID() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    guard status == noErr, deviceID != 0 else { return nil }
    return deviceID
  }

  private static func deviceName(deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(deviceID),
      &address,
      0,
      nil,
      &size,
      &name
    )

    guard status == noErr else { return nil }
    let s = name as String
    return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
  }

  private static func deviceNominalSampleRate(deviceID: AudioDeviceID) -> Double? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyNominalSampleRate,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var rate = Float64(0)
    var size = UInt32(MemoryLayout<Float64>.size)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(deviceID),
      &address,
      0,
      nil,
      &size,
      &rate
    )

    guard status == noErr, rate > 0 else { return nil }
    return rate
  }
}

