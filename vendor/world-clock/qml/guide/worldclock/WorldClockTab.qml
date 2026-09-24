import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../.."
import "../../reusables"

Item {
    id: tabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1 : 0
    property real slideY: visible ? 0 : rootObj.s(10)
    property var selectedResult: null

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    Behavior on opacity { NumberAnimation { duration: 250 } }
    transform: Translate { y: slideY }

    component ActionButton: Rectangle {
        id: actionRoot
        property string label: ""
        property string icon: ""
        property color accent: ThemeBackend.surface1
        property color foreground: ThemeBackend.text
        property bool compact: false
        signal clicked()

        implicitWidth: actionRow.implicitWidth + rootObj.s(compact ? 14 : 22)
        implicitHeight: rootObj.s(compact ? 30 : 36)
        radius: ThemeBackend.clampedBorderRadius
        color: !enabled ? Qt.alpha(accent, 0.4) : (actionMouse.containsMouse ? Qt.lighter(accent, 1.12) : accent)
        opacity: enabled ? 1 : 0.55

        RowLayout {
            id: actionRow
            anchors.centerIn: parent
            spacing: rootObj.s(6)
            Text {
                visible: actionRoot.icon !== ""
                text: actionRoot.icon
                font.family: "Iosevka Nerd Font"
                font.pixelSize: rootObj.s(actionRoot.compact ? 13 : 15)
                color: actionRoot.foreground
            }
            Text {
                visible: actionRoot.label !== ""
                text: actionRoot.label
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(actionRoot.compact ? 10 : 11)
                font.weight: Font.Bold
                color: actionRoot.foreground
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            enabled: actionRoot.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: actionRoot.clicked()
        }
    }

    function deactivate() {
        WorldClockService.settingsActive = false;
        WorldClockService.scheduleSearch("");
        selectedResult = null;
    }

    onVisibleChanged: {
        WorldClockService.settingsActive = visible;
        if (!visible)
            deactivate();
    }

    Component.onCompleted: WorldClockService.settingsActive = visible
    Component.onDestruction: deactivate()

    Flickable {
        anchors.fill: parent
        anchors.margins: rootObj.s(8)
        contentHeight: contentColumn.implicitHeight + rootObj.s(16)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: rootObj.s(12)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: rootObj.s(12)
                spacing: rootObj.s(4)
                Text {
                    text: I18n.t("guide.world_clock.title", "World Clock")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(22)
                    font.weight: Font.Black
                    color: ThemeBackend.text
                }
                Text {
                    text: I18n.t("guide.world_clock.description", "Choose the cities shown on the globe and configure its motion.")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(11)
                    color: ThemeBackend.subtext0
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: searchColumn.implicitHeight + rootObj.s(28)
                radius: ThemeBackend.clampedBorderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.72)
                border.color: Qt.alpha(ThemeBackend.surface2, 0.55)

                ColumnLayout {
                    id: searchColumn
                    anchors.fill: parent
                    anchors.margins: rootObj.s(14)
                    spacing: rootObj.s(10)

                    Text {
                        text: I18n.t("guide.world_clock.add_city", "Add a city")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(14)
                        font.weight: Font.Bold
                        color: ThemeBackend.text
                    }

                    Input {
                        id: searchInput
                        Layout.fillWidth: true
                        implicitHeight: rootObj.s(38)
                        placeholderText: I18n.t("guide.world_clock.search_placeholder", "Search a city or IANA timezone...")
                        leadingIcon: "󰍉"
                        showClearButton: true
                        baseColor: ThemeBackend.base
                        accentColor: ThemeBackend.sapphire
                        textColor: ThemeBackend.text
                        subTextColor: ThemeBackend.subtext0
                        borderColor: ThemeBackend.surface2
                        fontPixelSize: rootObj.s(11)
                        isBusy: WorldClockService.searchBusy
                        onTextEdited: text => {
                            tabRoot.selectedResult = null;
                            WorldClockService.scheduleSearch(text);
                        }
                        onCleared: {
                            tabRoot.selectedResult = null;
                            WorldClockService.scheduleSearch("");
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: tabRoot.selectedResult !== null
                        spacing: rootObj.s(10)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)
                            Text {
                                text: tabRoot.selectedResult ? tabRoot.selectedResult.place : ""
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(12)
                                font.weight: Font.Bold
                                color: ThemeBackend.sapphire
                            }
                            Text {
                                text: tabRoot.selectedResult ? tabRoot.selectedResult.timezone : ""
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(9)
                                color: ThemeBackend.subtext0
                            }
                        }

                        Input {
                            id: personalLabel
                            implicitWidth: rootObj.s(230)
                            implicitHeight: rootObj.s(34)
                            placeholderText: I18n.t("guide.world_clock.personal_label", "Personal label (optional)")
                            baseColor: ThemeBackend.base
                            accentColor: ThemeBackend.sapphire
                            textColor: ThemeBackend.text
                            borderColor: ThemeBackend.surface2
                            fontPixelSize: rootObj.s(10)
                        }

                        ActionButton {
                            label: I18n.t("guide.world_clock.add", "Add")
                            icon: "󰐕"
                            accent: ThemeBackend.sapphire
                            foreground: ThemeBackend.crust
                            onClicked: {
                                if (WorldClockService.addCity(tabRoot.selectedResult, personalLabel.text)) {
                                    personalLabel.clear();
                                    searchInput.clear();
                                    tabRoot.selectedResult = null;
                                    WorldClockService.scheduleSearch("");
                                }
                            }
                        }
                    }

                    Text {
                        visible: WorldClockService.searchBusy
                        text: I18n.t("guide.world_clock.searching", "Searching...")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(10)
                        color: ThemeBackend.peach
                    }

                    Text {
                        visible: !WorldClockService.searchBusy && WorldClockService.searchError !== ""
                        text: WorldClockService.searchError
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(10)
                        color: ThemeBackend.red
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: !WorldClockService.searchBusy
                            && WorldClockService.searchQuery.trim().length > 0
                            && WorldClockService.searchResults.length === 0
                            && WorldClockService.searchError === ""
                        text: I18n.t("guide.world_clock.no_results", "No matching cities")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(10)
                        color: ThemeBackend.subtext0
                    }

                    Repeater {
                        model: WorldClockService.searchResults
                        delegate: Rectangle {
                            id: resultCard
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(54)
                            radius: ThemeBackend.clampedBorderRadius
                            color: resultMouse.containsMouse || (tabRoot.selectedResult && tabRoot.selectedResult.place === modelData.place && tabRoot.selectedResult.timezone === modelData.timezone)
                                ? ThemeBackend.surface1 : Qt.alpha(ThemeBackend.base, 0.72)
                            border.color: modelData.source === "online" ? Qt.alpha(ThemeBackend.peach, 0.65) : Qt.alpha(ThemeBackend.surface2, 0.45)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: rootObj.s(12)
                                anchors.rightMargin: rootObj.s(12)
                                spacing: rootObj.s(10)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    RowLayout {
                                        spacing: rootObj.s(7)
                                        Text {
                                            text: modelData.place
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            font.weight: Font.Bold
                                            color: ThemeBackend.text
                                        }
                                        Rectangle {
                                            visible: modelData.source === "online"
                                            implicitWidth: onlineText.implicitWidth + rootObj.s(10)
                                            implicitHeight: onlineText.implicitHeight + rootObj.s(4)
                                            radius: height / 2
                                            color: Qt.alpha(ThemeBackend.peach, 0.18)
                                            Text {
                                                id: onlineText
                                                anchors.centerIn: parent
                                                text: I18n.t("guide.world_clock.online_result", "Online result")
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(8)
                                                font.weight: Font.Bold
                                                color: ThemeBackend.peach
                                            }
                                        }
                                    }
                                    Text {
                                        text: (modelData.subtitle ? modelData.subtitle + " · " : "") + modelData.timezone
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(9)
                                        color: ThemeBackend.subtext0
                                    }
                                }
                                Text {
                                    text: modelData.time + "  " + modelData.abbreviation
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                    font.weight: Font.Bold
                                    color: ThemeBackend.sapphire
                                }
                            }

                            MouseArea {
                                id: resultMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    tabRoot.selectedResult = modelData;
                                    personalLabel.text = "";
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface2, 0.45) }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(12)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: I18n.t("guide.world_clock.online_search", "Use online search fallback")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                color: ThemeBackend.text
                            }
                            Text {
                                text: I18n.t("guide.world_clock.online_search_desc", "Send the query to Open-Meteo only when the offline catalogue has no match.")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(9)
                                color: ThemeBackend.subtext0
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                        Toggle {
                            checked: WorldClockService.settings.onlineSearch
                            accentColor: ThemeBackend.sapphire
                            baseColor: ThemeBackend.surface1
                            textColor: ThemeBackend.text
                            onToggled: checked => WorldClockService.setOnlineSearch(checked)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: citiesColumn.implicitHeight + rootObj.s(28)
                radius: ThemeBackend.clampedBorderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.72)
                border.color: Qt.alpha(ThemeBackend.surface2, 0.55)

                ColumnLayout {
                    id: citiesColumn
                    anchors.fill: parent
                    anchors.margins: rootObj.s(14)
                    spacing: rootObj.s(9)

                    Text {
                        text: I18n.t("guide.world_clock.saved_cities", "Saved cities")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(14)
                        font.weight: Font.Bold
                        color: ThemeBackend.text
                    }

                    Repeater {
                        model: WorldClockService.cities
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(58)
                            radius: ThemeBackend.clampedBorderRadius
                            color: Qt.alpha(ThemeBackend.base, 0.72)
                            border.color: Qt.alpha(ThemeBackend.surface2, 0.45)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: rootObj.s(10)
                                spacing: rootObj.s(8)

                                ColumnLayout {
                                    Layout.preferredWidth: rootObj.s(180)
                                    spacing: 1
                                    Text {
                                        text: modelData.place
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(11)
                                        font.weight: Font.Bold
                                        color: ThemeBackend.text
                                    }
                                    Text {
                                        text: modelData.timezone
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(8)
                                        color: ThemeBackend.subtext0
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Input {
                                    Layout.fillWidth: true
                                    implicitHeight: rootObj.s(32)
                                    text: modelData.label
                                    baseColor: ThemeBackend.surface0
                                    accentColor: ThemeBackend.sapphire
                                    textColor: ThemeBackend.text
                                    borderColor: ThemeBackend.surface2
                                    fontPixelSize: rootObj.s(10)
                                    onAccepted: text => WorldClockService.setCityLabel(modelData.id, text)
                                }

                                ActionButton {
                                    compact: true
                                    icon: "󰁝"
                                    enabled: index > 0
                                    onClicked: WorldClockService.moveCity(modelData.id, -1)
                                    Accessible.name: I18n.t("guide.world_clock.move_up", "Move up")
                                }
                                ActionButton {
                                    compact: true
                                    icon: "󰁅"
                                    enabled: index < WorldClockService.cities.length - 1
                                    onClicked: WorldClockService.moveCity(modelData.id, 1)
                                    Accessible.name: I18n.t("guide.world_clock.move_down", "Move down")
                                }
                                ActionButton {
                                    compact: true
                                    icon: "󰆴"
                                    accent: Qt.alpha(ThemeBackend.red, 0.22)
                                    foreground: ThemeBackend.red
                                    onClicked: WorldClockService.removeCity(modelData.id)
                                    Accessible.name: I18n.t("guide.world_clock.remove", "Remove")
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: preferencesColumn.implicitHeight + rootObj.s(28)
                radius: ThemeBackend.clampedBorderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.72)
                border.color: Qt.alpha(ThemeBackend.surface2, 0.55)

                ColumnLayout {
                    id: preferencesColumn
                    anchors.fill: parent
                    anchors.margins: rootObj.s(14)
                    spacing: rootObj.s(14)

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("guide.world_clock.time_format", "Time format")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.text
                        }
                        Dropdown {
                            implicitWidth: rootObj.s(180)
                            options: [
                                I18n.t("guide.world_clock.follow_bar", "Follow bar"),
                                I18n.t("guide.world_clock.twelve_hour", "12-hour"),
                                I18n.t("guide.world_clock.twenty_four_hour", "24-hour")
                            ]
                            currentIndex: WorldClockService.settings.timeFormat === "12h" ? 1 : (WorldClockService.settings.timeFormat === "24h" ? 2 : 0)
                            accentColor: ThemeBackend.sapphire
                            baseColor: ThemeBackend.surface1
                            dropdownColor: ThemeBackend.surface0
                            borderColor: ThemeBackend.surface2
                            textColor: ThemeBackend.text
                            activeTextColor: ThemeBackend.crust
                            onValueChanged: index => WorldClockService.setTimeFormat(index === 1 ? "12h" : (index === 2 ? "24h" : "bar"))
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface2, 0.45) }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("guide.world_clock.auto_rotate", "Auto-rotate globe")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.text
                        }
                        Toggle {
                            checked: WorldClockService.globe.autoRotate
                            accentColor: ThemeBackend.sapphire
                            baseColor: ThemeBackend.surface1
                            onToggled: checked => WorldClockService.setAutoRotate(checked)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        enabled: WorldClockService.globe.autoRotate
                        opacity: enabled ? 1 : 0.5
                        spacing: rootObj.s(12)
                        Text {
                            text: I18n.t("guide.world_clock.rotation_speed", "Rotation speed")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.text
                        }
                        Slider {
                            id: speedSlider
                            Layout.fillWidth: true
                            from: 0.25
                            to: 12
                            stepSize: 0.25
                            value: WorldClockService.globe.rotationSpeed
                            onPressedChanged: {
                                if (!pressed)
                                    WorldClockService.setRotationSpeed(value);
                            }
                            background: Rectangle {
                                x: speedSlider.leftPadding
                                y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                                width: speedSlider.availableWidth
                                height: rootObj.s(4)
                                radius: height / 2
                                color: ThemeBackend.surface1
                                Rectangle {
                                    width: speedSlider.visualPosition * parent.width
                                    height: parent.height
                                    radius: parent.radius
                                    color: ThemeBackend.sapphire
                                }
                            }
                            handle: Rectangle {
                                x: speedSlider.leftPadding + speedSlider.visualPosition * (speedSlider.availableWidth - width)
                                y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                                implicitWidth: rootObj.s(17)
                                implicitHeight: rootObj.s(17)
                                radius: width / 2
                                color: ThemeBackend.sapphire
                                border.color: ThemeBackend.crust
                                border.width: rootObj.s(2)
                            }
                        }
                        Text {
                            text: Number(speedSlider.value).toFixed(2) + "°/s"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(10)
                            font.weight: Font.Bold
                            color: ThemeBackend.sapphire
                            Layout.preferredWidth: rootObj.s(62)
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
}
