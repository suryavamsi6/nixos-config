import QtQuick
import Quickshell
import Quickshell.Io
import "../../../reusables"
import "../../../"

Item {
    id: root
    property var barWindow
    property bool moduleActive: true
    implicitWidth: barWindow ? barWindow.s(34) : 34
    implicitHeight: barWindow ? barWindow.barHeight : 30
    width: implicitWidth
    height: implicitHeight
    enabled: moduleActive

    property bool popupActive: currentWidget.trim() === "worldclock"
    property string currentWidget: ""

    FileView {
        id: activeWidgetFile
        path: Caching.runDir + "/current_widget"
        watchChanges: true
        onLoaded: root.currentWidget = (typeof text === "function" ? text() : text) || ""
        onFileChanged: reload()
    }

    IconButton {
        id: globeButton
        anchors.centerIn: parent
        size: barWindow ? barWindow.s(30) : 30
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
        buttonIcon: "󰢷"
        iconFontSize: barWindow ? barWindow.s(16) : 16
        accentColor: root.popupActive ? ThemeBackend.blue : ThemeBackend.surface1
        textColor: root.popupActive ? ThemeBackend.base : (isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2)
        opacity: root.moduleActive ? 1 : 0
        onClicked: Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle worldclock"])
    }
}
