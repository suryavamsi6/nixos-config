#!/usr/bin/env python3
"""Report real Bluetooth battery percentages in Serpantinum's network popup.

Serpantinum reads battery from Quickshell's BlueZ proxy, which reports nothing
when BlueZ's battery plugin is disabled (ours is, deliberately — see
modules/desktop/serpantinum-bluetooth/bt_battery.sh). Upstream then coerces the
missing value to 0%:
    let battery = d.batteryAvailable ? Math.round(d.battery * 100) : 0;
so every connected device without a battery reads "0%".

This patch adds a `btBatteryLevels` cache filled by a poller that runs
`bt_battery.sh`, falls back to that cache when the proxy has no value, and skips
the battery row entirely when nothing is known — rather than lying with 0%.

Anchored on Serpantinum v2.3.2 (commit d282c4c018). The root object id is
`popupWindowRoot`; the older `window` alias this patch used to reference no
longer exists.
"""
from pathlib import Path
import sys


path = Path(sys.argv[1])
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    text = text.replace(old, new, 1)


# 1. Cache holder next to the existing bluetooth device/profile maps.
replace_once(
    """    property var btDeviceMap: ({})
    property var btAudioProfiles: ({})""",
    """    property var btDeviceMap: ({})
    property var btAudioProfiles: ({})
    property var btBatteryLevels: ({})""",
    "Bluetooth battery property",
)

# 2. Start the poller when a device connects while the popup is already open on
#    the Bluetooth tab. Upstream grew a `connectAfterLinkDrop` branch inside this
#    handler in 2.3.x, so anchor on the head of the function, not a one-liner.
replace_once(
    """                    function onConnectedChanged() {
                        popupWindowRoot.requestBtRebuild();""",
    """                    function onConnectedChanged() {
                        popupWindowRoot.requestBtRebuild();
                        if (device && device.connected && popupWindowRoot.activeMode === "bt" && !btBatteryPoller.running) btBatteryPoller.running = true;""",
    "Bluetooth connection refresh",
)

# 3. Popup-open refresh.
replace_once(
    """            if (popupWindowRoot.activeMode === "bt" && !btProfilePoller.running) btProfilePoller.running = true;""",
    """            if (popupWindowRoot.activeMode === "bt" && !btProfilePoller.running) btProfilePoller.running = true;
            if (popupWindowRoot.activeMode === "bt" && !btBatteryPoller.running) btBatteryPoller.running = true;""",
    "popup-open battery refresh",
)

# 4. Popup-close stop, alongside the existing profile poller teardown.
replace_once(
    """            btProfilePoller.running = false;
            ipFetcher.running = false;""",
    """            btProfilePoller.running = false;
            btBatteryPoller.running = false;
            ipFetcher.running = false;""",
    "popup-close battery stop",
)

# 5. Bluetooth-tab battery refresh.
replace_once(
    """        if (popupWindowRoot.activeMode === "bt" && popupWindowRoot.visible && !btProfilePoller.running) btProfilePoller.running = true;""",
    """        if (popupWindowRoot.activeMode === "bt" && popupWindowRoot.visible && !btProfilePoller.running) btProfilePoller.running = true;
        if (popupWindowRoot.activeMode === "bt" && popupWindowRoot.visible && !btBatteryPoller.running) btBatteryPoller.running = true;""",
    "Bluetooth-tab battery refresh",
)

# 6. Only render the battery info row when a percentage is actually known.
replace_once(
    """                    nodes.push({ id: "bat_" + obj.mac, name: (obj.battery || "0") + "%", icon: "󰥉", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });""",
    """                    if (obj.battery !== null && obj.battery !== undefined && obj.battery !== "") {
                        nodes.push({ id: "bat_" + obj.mac, name: obj.battery + "%", icon: "󰥉", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    }""",
    "battery info node",
)

# 7. Prefer the proxy value, fall back to the cache, and leave it null when
#    neither source knows — so step 6 can decide whether to show the row.
replace_once(
    """            let connected = d.connected;
            let battery = d.batteryAvailable ? Math.round(d.battery * 100) : 0;
            let iconType = d.icon || "";""",
    """            let connected = d.connected;
            let cachedBattery = popupWindowRoot.btBatteryLevels[String(mac).toLowerCase()];
            let battery = d.batteryAvailable
                ? Math.round(d.battery * 100)
                : (cachedBattery !== undefined ? Number(cachedBattery) : null);
            let iconType = d.icon || "";""",
    "battery value selection",
)

# 8. Keep null intact rather than stringifying it.
replace_once(
    """                    battery: battery.toString(),""",
    """                    battery: battery,""",
    "connected-device battery value",
)

# 9. The poller itself, inserted just before the main poll timer.
process_anchor = """    Timer {
        id: mainPollerTimer"""
process_block = """    Process {
        id: btBatteryPoller
        command: ["bash", popupWindowRoot.scriptsDir + "/bt_battery.sh"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let levels = JSON.parse(this.text.trim() || "{}");
                    if (!popupWindowRoot.deepEqual(popupWindowRoot.btBatteryLevels, levels)) {
                        popupWindowRoot.btBatteryLevels = levels;
                        popupWindowRoot.requestBtRebuild();
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        id: btBatteryRefreshTimer
        interval: 60000
        running: popupWindowRoot.visible && popupWindowRoot.activeMode === "bt"
        repeat: true
        onTriggered: {
            if (!btBatteryPoller.running) btBatteryPoller.running = true;
        }
    }

    Timer {
        id: mainPollerTimer"""
replace_once(process_anchor, process_block, "Bluetooth battery process")

path.write_text(text)
