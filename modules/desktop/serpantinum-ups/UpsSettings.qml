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
    property int draftBatteryLevel: 50
    property int draftMinutes: 5
    property bool dirty: false
    property bool saved: false

    function storedUpsSettings() {
        if (Config.rawSettings && Config.rawSettings.ups)
            return Config.rawSettings.ups;
        return {};
    }

    function syncDrafts() {
        if (dirty)
            return;
        let settings = storedUpsSettings();
        draftBatteryLevel = Math.max(5, Math.min(90, Number(settings.shutdownBatteryLevel || 50)));
        draftMinutes = Math.max(1, Math.min(60, Number(settings.shutdownMinutes || 5)));
    }

    function applyPolicy() {
        Config.updateJsonBulk({
            "ups": {
                "shutdownBatteryLevel": draftBatteryLevel,
                "shutdownMinutes": draftMinutes
            }
        });
        dirty = false;
        saved = true;
        savedTimer.restart();
    }

    function refreshTelemetry() {
        if (!telemetryProcess.running)
            telemetryProcess.running = true;
    }

    onVisibleChanged: {
        if (visible) {
            syncDrafts();
            refreshTelemetry();
        }
    }

    Connections {
        target: Config
        function onSettingsLoaded() { root.syncDrafts(); }
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

    Timer {
        id: savedTimer
        interval: 1800
        onTriggered: root.saved = false
    }

    component StepButton : Rectangle {
        property string symbol: "+"
        signal activated()
        implicitWidth: 28
        implicitHeight: 28
        radius: 8
        color: stepMouse.containsMouse ? ThemeBackend.surface2 : ThemeBackend.surface1
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.text, 0.08)

        Text {
            anchors.centerIn: parent
            text: parent.symbol
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.pixelSize: 16
            font.weight: Font.Bold
        }
        MouseArea {
            id: stepMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
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

            Text {
                text: root.saved ? "Applied" : (root.dirty ? "Not applied" : "Active")
                color: root.saved ? ThemeBackend.green : (root.dirty ? ThemeBackend.yellow : ThemeBackend.subtext0)
                font.family: ThemeBackend.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "Shut down at"
                color: ThemeBackend.subtext0
                font.family: ThemeBackend.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
            }

            StepButton {
                symbol: "−"
                onActivated: {
                    root.draftBatteryLevel = Math.max(5, root.draftBatteryLevel - 5);
                    root.dirty = true;
                }
            }
            Text {
                text: root.draftBatteryLevel + "%"
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: 12
                font.weight: Font.Black
                Layout.minimumWidth: 36
                horizontalAlignment: Text.AlignHCenter
            }
            StepButton {
                onActivated: {
                    root.draftBatteryLevel = Math.min(90, root.draftBatteryLevel + 5);
                    root.dirty = true;
                }
            }

            Text {
                text: "or"
                color: ThemeBackend.overlay1
                font.family: ThemeBackend.fontFamily
                font.pixelSize: 10
            }

            StepButton {
                symbol: "−"
                onActivated: {
                    root.draftMinutes = Math.max(1, root.draftMinutes - 1);
                    root.dirty = true;
                }
            }
            Text {
                text: root.draftMinutes + " min"
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: 12
                font.weight: Font.Black
                Layout.minimumWidth: 48
                horizontalAlignment: Text.AlignHCenter
            }
            StepButton {
                onActivated: {
                    root.draftMinutes = Math.min(60, root.draftMinutes + 1);
                    root.dirty = true;
                }
            }

            Item { Layout.fillWidth: true }

            ClickButton {
                implicitWidth: 66
                implicitHeight: 28
                buttonText: "Apply"
                textFontSize: 10
                horizontalPadding: 10
                cornerRadius: 8
                accentColor: root.dirty ? ThemeBackend.blue : ThemeBackend.surface1
                textColor: root.dirty ? ThemeBackend.crust : ThemeBackend.overlay1
                enabled: root.dirty
                onClicked: root.applyPolicy()
            }
        }
    }
}
