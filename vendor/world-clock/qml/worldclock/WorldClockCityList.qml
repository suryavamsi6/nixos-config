import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

Item {
    id: root

    property var cities: []
    property var clocks: []
    property var errors: []
    property string selectedCityId: ""
    signal citySelected(string cityId)

    function clockFor(cityId) {
        for (let index = 0; index < clocks.length; index++) {
            if (clocks[index].id === cityId)
                return clocks[index];
        }
        return null;
    }

    function errorFor(cityId) {
        for (let index = 0; index < errors.length; index++) {
            if (errors[index].id === cityId)
                return errors[index];
        }
        return null;
    }

    function localizedDay(clock) {
        if (!clock)
            return "";
        if (clock.day_delta === -1)
            return I18n.t("worldclock.yesterday", "Yesterday");
        if (clock.day_delta === 0)
            return I18n.t("worldclock.today", "Today");
        if (clock.day_delta === 1)
            return I18n.t("worldclock.tomorrow", "Tomorrow");
        return clock.day_label || clock.date;
    }

    ListView {
        id: cityView
        anchors.fill: parent
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: root.cities
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property var clock: root.clockFor(modelData.id)
            readonly property var cityError: root.errorFor(modelData.id)
            readonly property bool selected: root.selectedCityId === modelData.id

            width: cityView.width - 8
            height: 104
            radius: ThemeBackend.clampedBorderRadius
            color: selected
                ? Qt.alpha(ThemeBackend.sapphire, 0.17)
                : (cardMouse.containsMouse ? ThemeBackend.surface1 : Qt.alpha(ThemeBackend.surface0, 0.78))
            border.width: selected ? 2 : 1
            border.color: selected ? ThemeBackend.sapphire : Qt.alpha(ThemeBackend.surface2, 0.55)

            Behavior on color { ColorAnimation { duration: 170 } }
            Behavior on border.color { ColorAnimation { duration: 170 } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: modelData.label || modelData.place
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Black
                            color: card.selected ? ThemeBackend.sapphire : ThemeBackend.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.label && modelData.label !== modelData.place ? modelData.place : modelData.timezone
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 9
                            color: ThemeBackend.subtext0
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    Text {
                        visible: card.clock !== null
                        text: card.clock ? card.clock.time : ""
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.Black
                        color: ThemeBackend.text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: card.clock !== null
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: card.clock ? card.clock.date + " · " + root.localizedDay(card.clock) : ""
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 9
                        color: card.clock && card.clock.day_delta !== 0 ? ThemeBackend.peach : ThemeBackend.subtext0
                        elide: Text.ElideRight
                    }
                    Text {
                        text: card.clock ? card.clock.abbreviation : ""
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: ThemeBackend.sapphire
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: card.clock === null
                    spacing: 7
                    Text {
                        text: card.cityError ? "󰅚" : "󰔟"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: 11
                        color: card.cityError ? ThemeBackend.red : ThemeBackend.subtext0
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.cityError ? card.cityError.message : I18n.t("worldclock.loading", "Updating world times...")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 9
                        color: card.cityError ? ThemeBackend.red : ThemeBackend.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }

            MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.citySelected(modelData.id)
            }
        }
    }
}
