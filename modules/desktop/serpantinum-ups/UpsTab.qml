import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

Item {
    id: root
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: rootObj.s(28)
        spacing: rootObj.s(18)

        Text {
            text: "UPS"
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(28)
            font.weight: Font.Black
        }

        Text {
            text: "APC Back-UPS RS 1500G-IN"
            color: ThemeBackend.subtext0
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(13)
            font.weight: Font.Bold
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: rootObj.s(170)
            radius: rootObj.s(16)
            color: ThemeBackend.surface0
            border.width: 1
            border.color: Qt.alpha(ThemeBackend.text, 0.08)
            Loader {
                anchors.fill: parent
                anchors.margins: rootObj.s(18)
                source: "UpsSettings.qml"
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Read-only telemetry from apcupsd. The shutdown policy is fixed in NixOS (modules/hardware/apcupsd.nix): power off at 5% battery or after 1 minute on battery, whichever comes first. Runtime and load are estimates from the UPS and can change sharply under gaming load."
            wrapMode: Text.WordWrap
            color: ThemeBackend.overlay1
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(11)
        }

        Text {
            Layout.fillWidth: true
            text: "Change it by editing modules/hardware/apcupsd.nix and running nh os switch."
            wrapMode: Text.WordWrap
            color: ThemeBackend.overlay1
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(11)
        }

        Item { Layout.fillHeight: true }
    }
}
