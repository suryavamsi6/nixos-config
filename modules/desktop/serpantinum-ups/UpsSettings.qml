import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../reusables"
import "../singletons"

Item {
    id: root

    property int capacity: 0
    property string statusText: "Unknown"
    property int hoursRemaining: 0
    property int minutesRemaining: 0
    property var telemetry: ({})

    function refreshTelemetry() {
        if (!telemetryProcess.running)
            telemetryProcess.running = true;
    }

    onVisibleChanged: {
        if (visible)
            refreshTelemetry();
    }

    Process {
        id: telemetryProcess
        running: false
        command: ["bash", Caching.serpantinumDir + "/scripts/system/ups_status.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(this.text.trim());
                    if (parsed && typeof parsed === "object")
                        root.telemetry = parsed;
                } catch (error) {
                    root.telemetry = {};
                }
            }
        }
    }

    Timer {
        running: root.visible
        interval: 5000
        repeat: true
        onTriggered: root.refreshTelemetry()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: "APC UPS · " + String(root.telemetry.status || root.statusText)
                    color: ThemeBackend.text
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Black
                }
                Text {
                    text: {
                        let charge = Number(root.telemetry.charge || root.capacity);
                        let runtime = Number(root.telemetry.runtime || (root.hoursRemaining * 60 + root.minutesRemaining));
                        let load = Number(root.telemetry.load || 0);
                        return Math.round(charge) + "% charge  ·  " + runtime.toFixed(1) + " min  ·  " + load.toFixed(0) + "% load";
                    }
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
                Text {
                    visible: Number(root.telemetry.batteryVoltage || 0) > 0
                    text: Number(root.telemetry.batteryVoltage || 0).toFixed(1) + " V battery  ·  Last transfer: " + String(root.telemetry.lastTransfer || "Unknown")
                    color: ThemeBackend.overlay1
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: 8
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }
}
