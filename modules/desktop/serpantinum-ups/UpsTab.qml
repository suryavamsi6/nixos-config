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
            text: "The UPS agent monitors the USB-connected battery. Changes are applied automatically to apcupsd after you press Apply. Runtime and load are estimates from the UPS and can change sharply under gaming load."
            wrapMode: Text.WordWrap
            color: ThemeBackend.overlay1
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(11)
        }

        Item { Layout.fillHeight: true }
    }
}
