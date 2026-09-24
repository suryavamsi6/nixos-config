import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import ".."

Item {
    id: root

    property real targetMasterWidth: 1080
    property real targetMasterHeight: 620
    property string selectedCityId: ""
    readonly property bool panelIsActive: StackView.status === StackView.Active

    function ensureSelection() {
        let list = WorldClockService.cities;
        let found = false;
        for (let index = 0; index < list.length; index++) {
            if (list[index].id === selectedCityId) {
                found = true;
                break;
            }
        }
        if (!found)
            selectedCityId = list.length > 0 ? list[0].id : "";
    }

    function setActive(value) {
        WorldClockService.panelActive = value;
        if (value) {
            ensureSelection();
            WorldClockService.refreshSnapshot();
        }
    }

    function openSettings() {
        if (!Caching.serpantinumDir)
            return;
        Quickshell.execDetached([
            "bash",
            Caching.serpantinumDir + "/scripts/qs_manager.sh",
            "toggle",
            "guide",
            "WorldClock"
        ]);
    }

    onPanelIsActiveChanged: setActive(panelIsActive)
    Component.onCompleted: setActive(panelIsActive)
    Component.onDestruction: setActive(false)

    Connections {
        target: WorldClockService
        function onCitiesChanged() { root.ensureSelection(); }
    }

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: ThemeBackend.base
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.surface2, 0.7)
        clip: true

        Rectangle {
            anchors.fill: parent
            opacity: 0.16
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(ThemeBackend.sapphire, 0.42) }
                GradientStop { position: 0.48; color: "transparent" }
                GradientStop { position: 1; color: Qt.alpha(ThemeBackend.mauve, 0.22) }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                spacing: 10

                Text {
                    text: "󰖟"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: 24
                    color: ThemeBackend.sapphire
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: I18n.t("worldclock.title", "World Clock")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Black
                        color: ThemeBackend.text
                    }
                    Text {
                        text: WorldClockService.snapshot.generated_at
                            ? "Updated " + Qt.formatDateTime(new Date(WorldClockService.snapshot.generated_at), "HH:mm:ss")
                            : I18n.t("worldclock.loading", "Updating world times...")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 9
                        color: ThemeBackend.subtext0
                    }
                }

                Rectangle {
                    visible: WorldClockService.snapshotBusy
                    implicitWidth: busyRow.implicitWidth + 18
                    implicitHeight: 28
                    radius: height / 2
                    color: Qt.alpha(ThemeBackend.peach, 0.14)
                    RowLayout {
                        id: busyRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "󰔟"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: 11
                            color: ThemeBackend.peach
                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1200
                                loops: Animation.Infinite
                                running: WorldClockService.snapshotBusy
                            }
                        }
                        Text {
                            text: I18n.t("worldclock.loading", "Updating world times...")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 9
                            color: ThemeBackend.peach
                        }
                    }
                }

                Rectangle {
                    id: settingsButton
                    implicitWidth: settingsRow.implicitWidth + 20
                    implicitHeight: 34
                    radius: ThemeBackend.clampedBorderRadius
                    color: settingsMouse.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0
                    border.color: Qt.alpha(ThemeBackend.surface2, 0.65)
                    RowLayout {
                        id: settingsRow
                        anchors.centerIn: parent
                        spacing: 7
                        Text {
                            text: "󰒓"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: 14
                            color: ThemeBackend.sapphire
                        }
                        Text {
                            text: I18n.t("worldclock.settings", "World Clock settings")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: ThemeBackend.text
                        }
                    }
                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openSettings()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.alpha(ThemeBackend.surface2, 0.5)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                Item {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    Layout.minimumWidth: 640

                    WorldClockGlobe {
                        id: globe
                        anchors.fill: parent
                        active: root.panelIsActive
                        cities: WorldClockService.cities
                        clocks: WorldClockService.clocks
                        selectedCityId: root.selectedCityId
                        onCitySelected: cityId => root.selectedCityId = cityId
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: WorldClockService.cities.length === 0
                        spacing: 12
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "󰖟"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: 54
                            color: Qt.alpha(ThemeBackend.sapphire, 0.58)
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.t("worldclock.empty_title", "No cities configured")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 17
                            font.weight: Font.Black
                            color: ThemeBackend.text
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.t("worldclock.empty_body", "Add cities in Settings to place them on the globe.")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 10
                            color: ThemeBackend.subtext0
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: emptyActionText.implicitWidth + 24
                            implicitHeight: 36
                            radius: ThemeBackend.clampedBorderRadius
                            color: emptyActionMouse.containsMouse ? Qt.lighter(ThemeBackend.sapphire, 1.1) : ThemeBackend.sapphire
                            Text {
                                id: emptyActionText
                                anchors.centerIn: parent
                                text: I18n.t("worldclock.open_settings", "Open Settings")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: ThemeBackend.crust
                            }
                            MouseArea {
                                id: emptyActionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openSettings()
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        height: backendErrorRow.implicitHeight + 18
                        radius: ThemeBackend.clampedBorderRadius
                        visible: !WorldClockService.backendAvailable && WorldClockService.backendError !== ""
                        color: Qt.alpha(ThemeBackend.red, 0.15)
                        border.color: Qt.alpha(ThemeBackend.red, 0.5)
                        RowLayout {
                            id: backendErrorRow
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 8
                            Text {
                                text: "󰅚"
                                font.family: "Iosevka Nerd Font"
                                color: ThemeBackend.red
                            }
                            Text {
                                Layout.fillWidth: true
                                text: I18n.t("worldclock.backend_error", "World Clock could not update") + ": " + WorldClockService.backendError
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: 9
                                color: ThemeBackend.red
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    width: 1
                    color: Qt.alpha(ThemeBackend.surface2, 0.5)
                }

                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 334
                    Layout.maximumWidth: 350
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("guide.world_clock.saved_cities", "Saved cities")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: ThemeBackend.text
                        }
                        Text {
                            text: String(WorldClockService.cities.length)
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: ThemeBackend.sapphire
                        }
                    }

                    WorldClockCityList {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        cities: WorldClockService.cities
                        clocks: WorldClockService.clocks
                        errors: WorldClockService.snapshotErrors
                        selectedCityId: root.selectedCityId
                        onCitySelected: cityId => root.selectedCityId = cityId
                    }
                }
            }
        }
    }
}
