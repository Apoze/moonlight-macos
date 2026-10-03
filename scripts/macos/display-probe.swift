import AppKit
import CoreGraphics

let displays: [[String: Any]] = NSScreen.screens.compactMap { screen in
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
    let id = CGDirectDisplayID(number.uint32Value)
    let mode = CGDisplayCopyDisplayMode(id)
    return ["name": screen.localizedName, "id": id,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "builtIn": CGDisplayIsBuiltin(id) != 0,
            "active": CGDisplayIsActive(id) != 0,
            "mirrored": CGDisplayIsInMirrorSet(id) != 0,
            "main": CGDisplayIsMain(id) != 0,
            "width": mode?.pixelWidth ?? 0, "height": mode?.pixelHeight ?? 0,
            "nominalHz": mode?.refreshRate ?? 0,
            "minRefreshMs": screen.minimumRefreshInterval * 1000,
            "maxRefreshMs": screen.maximumRefreshInterval * 1000,
            "updateGranularityMs": screen.displayUpdateGranularity * 1000]
}
let data = try JSONSerialization.data(withJSONObject: displays, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
if CommandLine.arguments.contains("--check-builtin") && !displays.contains(where: {
    ($0["builtIn"] as? Bool == true) && ($0["active"] as? Bool == true) && ($0["mirrored"] as? Bool == false)
}) {
    fputs("An active, unmirrored built-in display is required. Open the MacBook lid.\n", stderr)
    exit(2)
}
