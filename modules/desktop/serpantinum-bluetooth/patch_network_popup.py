#!/usr/bin/env python3
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


replace_once(
    """    property var btDeviceMap: ({})
    property var btAudioProfiles: ({})""",
    """    property var btDeviceMap: ({})
    property var btAudioProfiles: ({})
    property var btBatteryLevels: ({})""",
    "Bluetooth battery property",
)

replace_once(
    """                    function onConnectedChanged() { window.requestBtRebuild(); }""",
    """                    function onConnectedChanged() {
                        window.requestBtRebuild();
                        if (device && device.connected && window.activeMode === "bt" && !btBatteryPoller.running) btBatteryPoller.running = true;
                    }""",
    "Bluetooth connection refresh",
)

replace_once(
    """            if (window.activeMode === "bt" && !btProfilePoller.running) btProfilePoller.running = true;""",
    """            if (window.activeMode === "bt" && !btProfilePoller.running) btProfilePoller.running = true;
            if (window.activeMode === "bt" && !btBatteryPoller.running) btBatteryPoller.running = true;""",
    "popup-open battery refresh",
)

replace_once(
    """            btProfilePoller.running = false;
            ipFetcher.running = false;""",
    """            btProfilePoller.running = false;
            btBatteryPoller.running = false;
            ipFetcher.running = false;""",
    "popup-close battery stop",
)

replace_once(
    """        if (window.activeMode === "bt" && window.visible && !btProfilePoller.running) btProfilePoller.running = true;""",
    """        if (window.activeMode === "bt" && window.visible && !btProfilePoller.running) btProfilePoller.running = true;
        if (window.activeMode === "bt" && window.visible && !btBatteryPoller.running) btBatteryPoller.running = true;""",
    "Bluetooth-tab battery refresh",
)

replace_once(
    """                    nodes.push({ id: "bat_" + obj.mac, name: (obj.battery || "0") + "%", icon: "󰥉", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });""",
    """                    if (obj.battery !== null && obj.battery !== undefined) {
                        nodes.push({ id: "bat_" + obj.mac, name: obj.battery + "%", icon: "󰥉", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    }""",
    "battery info node",
)

replace_once(
    """            let connected = d.connected;
            let battery = d.batteryAvailable ? Math.round(d.battery * 100) : 0;
            let iconType = d.icon || "";""",
    """            let connected = d.connected;
            let cachedBattery = window.btBatteryLevels[String(mac).toLowerCase()];
            let battery = d.batteryAvailable
                ? Math.round(d.battery * 100)
                : (cachedBattery !== undefined ? Number(cachedBattery) : null);
            let iconType = d.icon || "";""",
    "battery value selection",
)

replace_once(
    """                    battery: battery.toString(),""",
    """                    battery: battery,""",
    "connected-device battery value",
)

process_anchor = """    Timer {
        id: mainPollerTimer"""
process_block = """    Process {
        id: btBatteryPoller
        command: ["bash", window.scriptsDir + "/bt_battery.sh"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let levels = JSON.parse(this.text.trim() || "{}");
                    if (!window.deepEqual(window.btBatteryLevels, levels)) {
                        window.btBatteryLevels = levels;
                        window.requestBtRebuild();
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        id: btBatteryRefreshTimer
        interval: 60000
        running: window.visible && window.activeMode === "bt"
        repeat: true
        onTriggered: {
            if (!btBatteryPoller.running) btBatteryPoller.running = true;
        }
    }

    Timer {
        id: mainPollerTimer"""
replace_once(process_anchor, process_block, "Bluetooth battery process")

path.write_text(text)
