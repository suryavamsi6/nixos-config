import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../singletons"
import "."

Item {
    id: root
    focus: true
    property real targetMasterWidth: Scaler.s(1180)
    property real targetMasterHeight: Scaler.s(640)
    implicitWidth: targetMasterWidth
    implicitHeight: targetMasterHeight
    width: targetMasterWidth
    height: targetMasterHeight

    property var defaults: [
        { label: "Local", zone: "local" },
        { label: "UTC", zone: "UTC" },
        { label: "New York", zone: "America/New_York" },
        { label: "London", zone: "Europe/London" },
        { label: "Tokyo", zone: "Asia/Tokyo" }
    ]
    property var settings: (Config.rawSettings && Config.rawSettings.worldClock) ? Config.rawSettings.worldClock : ({})
    property var regions: settings.regions || defaults
    property bool hour12: settings.hour12 === null || settings.hour12 === undefined ? DateTime.is12Hour : Boolean(settings.hour12)
    property bool showSeconds: settings.showSeconds === undefined ? false : Boolean(settings.showSeconds)
    property var clocks: []
    property var catalogResults: []
    property int selectedIndex: 0
    property bool editing: false
    property string errorText: ""
    property string searchText: ""

    function save() {
        Config.setSetting("worldClock", { regions: regions, hour12: settings.hour12 === undefined ? null : settings.hour12, showSeconds: showSeconds, globe: settings.globe || ({ idleRotation: true }) })
    }
    function refresh() {
        snapshotProcess.running = false
        snapshotProcess.running = true
    }
    function removeRegion(i) {
        if (regions.length <= 1) return
        let next = regions.slice()
        next.splice(i, 1)
        regions = next
        save()
        refresh()
    }
    function moveRegion(i, direction) {
        let j = i + direction
        if (j < 0 || j >= regions.length) return
        let next = regions.slice()
        let item = next[i]
        next[i] = next[j]
        next[j] = item
        regions = next
        save()
    }
    function addZone(zone, label) {
        if (regions.length >= 12) return
        for (let i = 0; i < regions.length; i++) if (regions[i].zone === zone) return
        let next = regions.slice()
        next.push({ label: label, zone: zone })
        regions = next
        searchText = ""
        save()
        refresh()
    }
    function resetDefaults() {
        regions = defaults
        save()
        refresh()
    }
    function timeFor(item) {
        if (!item) return "--:--"
        if (!hour12) return showSeconds ? item.time : item.time.substring(0, 5)
        let parts = item.time.split(":")
        let h = Number(parts[0])
        let suffix = h >= 12 ? " PM" : " AM"
        h = h % 12
        if (h === 0) h = 12
        return h + ":" + parts[1] + (showSeconds ? ":" + parts[2] : "") + suffix
    }

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: ThemeBackend.base
        border.color: ThemeBackend.surface0
        border.width: 1
        clip: true
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Scaler.s(18)
        spacing: Scaler.s(12)
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "WORLD CLOCK // ORBITAL TIME"
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(18)
                font.weight: Font.Black
            }
            Item { Layout.fillWidth: true }
            Text {
                text: root.errorText
                color: ThemeBackend.red
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                elide: Text.ElideRight
            }
            IconButton {
                size: Scaler.s(30)
                buttonIcon: root.editing ? "󰌶" : "󰏫"
                iconFontSize: Scaler.s(15)
                accentColor: root.editing ? ThemeBackend.blue : ThemeBackend.surface1
                onClicked: root.editing = !root.editing
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Scaler.s(12)
            Rectangle {
                Layout.preferredWidth: Scaler.s(345)
                Layout.fillHeight: true
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.35)
                border.color: Qt.alpha(ThemeBackend.surface1, 0.75)
                border.width: 1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Scaler.s(12)
                    spacing: Scaler.s(8)
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "REGIONS"
                            color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(11)
                            font.weight: Font.Black
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: regions.length + "/12"
                            color: ThemeBackend.overlay1
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(10)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.editing
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            placeholderText: "Search IANA cities"
                            text: root.searchText
                            color: ThemeBackend.text
                            placeholderTextColor: ThemeBackend.overlay1
                            onTextChanged: root.searchText = text
                            background: Rectangle {
                                color: ThemeBackend.base
                                radius: 6
                                border.color: ThemeBackend.surface1
                            }
                        }
                        IconButton {
                            size: Scaler.s(28)
                            buttonIcon: "󰍉"
                            iconFontSize: Scaler.s(14)
                            onClicked: catalogProcess.restart()
                        }
                    }
                    ListView {
                        id: catalogView
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.editing ? Scaler.s(100) : 0
                        visible: root.editing
                        clip: true
                        model: root.catalogResults
                        delegate: Rectangle {
                            width: catalogView.width
                            height: Scaler.s(28)
                            color: addMouse.containsMouse ? ThemeBackend.surface1 : "transparent"
                            radius: 4
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label + " · " + modelData.zone
                                    color: ThemeBackend.text
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: Scaler.s(10)
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "+"
                                    color: ThemeBackend.teal
                                    font.pixelSize: Scaler.s(16)
                                }
                            }
                            MouseArea {
                                id: addMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.addZone(modelData.zone, modelData.label)
                            }
                        }
                    }
                    ListView {
                        id: clockList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Scaler.s(6)
                        model: root.clocks
                        delegate: Rectangle {
                            width: clockList.width
                            height: Scaler.s(67)
                            radius: 8
                            color: index === root.selectedIndex ? Qt.alpha(ThemeBackend.blue, 0.17) : ThemeBackend.base
                            border.color: index === root.selectedIndex ? ThemeBackend.blue : ThemeBackend.surface0
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: modelData.label
                                        color: ThemeBackend.text
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.Bold
                                        font.pixelSize: Scaler.s(11)
                                    }
                                    Text {
                                        text: modelData.abbr + "  " + modelData.offset + (modelData.dayDelta === 0 ? "" : "  D" + (modelData.dayDelta > 0 ? "+" : "") + modelData.dayDelta)
                                        color: ThemeBackend.subtext0
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: Scaler.s(9)
                                    }
                                }
                                Text {
                                    text: root.timeFor(modelData)
                                    color: modelData.isDay ? ThemeBackend.peach : ThemeBackend.blue
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Black
                                    font.pixelSize: Scaler.s(18)
                                }
                                Text {
                                    visible: root.editing
                                    text: "↑"
                                    color: ThemeBackend.overlay1
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.moveRegion(index, -1)
                                    }
                                }
                                Text {
                                    visible: root.editing
                                    text: "↓"
                                    color: ThemeBackend.overlay1
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.moveRegion(index, 1)
                                    }
                                }
                                Text {
                                    visible: root.editing
                                    text: "×"
                                    color: ThemeBackend.red
                                    font.pixelSize: Scaler.s(16)
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.removeRegion(index)
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                onClicked: root.selectedIndex = index
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.editing
                        Button {
                            text: "RESET"
                            onClicked: root.resetDefaults()
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: root.hour12 ? "12H" : "24H"
                            onClicked: {
                                root.hour12 = !root.hour12
                                let next = Object.assign({}, root.settings, { hour12: root.hour12 })
                                root.settings = next
                                root.save()
                            }
                        }
                        Button {
                            text: root.showSeconds ? "SEC ON" : "SEC OFF"
                            onClicked: {
                                root.showSeconds = !root.showSeconds
                                root.save()
                            }
                        }
                    }
                }
            }
            WorldClockGlobe {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clocks: root.clocks
                selectedIndex: root.selectedIndex
                active: root.visible
                onMarkerSelected: index => root.selectedIndex = index
            }
        }
    }

    Process {
        id: snapshotProcess
        command: [Caching.serpantinumDir + "/scripts/world_clock.py", "--zones", root.regions.map(r => r.zone).join(",")]
        running: root.visible
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(text)
                    root.clocks = parsed.clocks || []
                    root.errorText = (parsed.errors || []).map(e => e.zone).join(", ")
                } catch (e) {
                    root.errorText = "TIME DATA UNAVAILABLE"
                }
            }
        }
    }
    Process {
        id: catalogProcess
        command: [Caching.serpantinumDir + "/scripts/world_clock.py", "--catalog", "--search", root.searchText]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.catalogResults = JSON.parse(text).catalog || [] } catch (e) { root.catalogResults = [] }
            }
        }
    }
    Timer {
        interval: 60000
        running: root.visible
        repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: root.refresh()
}
