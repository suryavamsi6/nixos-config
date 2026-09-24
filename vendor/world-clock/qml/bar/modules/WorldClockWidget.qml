import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../"

Rectangle {
    id: root

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    readonly property bool isBottomBar: barWindow ? barWindow.barPosition === "bottom" : false

    property real targetX: 0
    property int animDuration: 600
    property bool showLayout: false
    property bool isHovered: mouseArea.containsMouse
    property bool togglePending: false
    property real horizontalPadding: barWindow ? barWindow.s(isCompact ? 10 : 12) : (isCompact ? 10 : 12)
    property real targetHeight: barWindow
        ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight))
        : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    property real targetWidth: moduleActive ? contentRow.implicitWidth + horizontalPadding * 2 : 0

    readonly property string localTime: {
        if (typeof DateTime !== "undefined" && DateTime.timeOnly !== undefined)
            return DateTime.timeOnly;
        return Qt.formatTime(new Date(), "HH:mm");
    }

    x: targetX
    y: barWindow ? barWindow.baseOffsetY + (barWindow.barHeight - targetHeight) / 2 : 0
    width: targetWidth
    height: targetHeight
    color: "transparent"
    border.width: 0
    clip: true
    visible: (width > 0 || opacity > 0) && (!barWindow || !barWindow.positionChanging)
    opacity: showLayout && moduleActive && (!barWindow || !barWindow.positionChanging)
        ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
        : 0.0

    Accessible.role: Accessible.Button
    Accessible.name: "World Clock, " + localTime

    Behavior on x {
        enabled: barWindow && barWindow.startupCascadeFinished && !barWindow.positionChanging
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on y {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on width {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on height {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on opacity {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: 550; easing.type: Easing.OutCubic }
    }

    transform: Translate {
        y: root.showLayout ? 0 : (barWindow ? (root.isBottomBar ? barWindow.s(20) : barWindow.s(-20)) : -20)
        Behavior on y {
            enabled: barWindow ? !barWindow.positionChanging : true
            NumberAnimation { duration: 800; easing.type: Easing.OutQuint }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: root.isGrouped
            ? "transparent"
            : (root.isSolid
                ? (root.distinctPills
                    ? (root.isHovered ? ThemeBackend.surface0 : Qt.darker(ThemeBackend.surface0, 1.15))
                    : "transparent")
                : (root.isHovered ? ThemeBackend.surface0 : ThemeBackend.base))
        border.width: 0

        Behavior on color {
            enabled: barWindow ? !barWindow.positionChanging : true
            ColorAnimation { duration: 250 }
        }
    }

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.s(6) : 6

        Item {
            Layout.preferredWidth: barWindow ? barWindow.s(root.isCompact ? 16 : 18) : (root.isCompact ? 16 : 18)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter

            Canvas {
                id: earthIcon
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    let context = getContext("2d");
                    let centerX = width / 2;
                    let centerY = height / 2;
                    let radius = Math.min(width, height) / 2 - 0.75;
                    context.clearRect(0, 0, width, height);
                    context.fillStyle = "#07090d";
                    context.strokeStyle = "rgba(255,255,255,0.82)";
                    context.lineWidth = 1;
                    context.beginPath();
                    context.arc(centerX, centerY, radius, 0, Math.PI * 2);
                    context.fill();
                    context.stroke();

                    context.strokeStyle = "rgba(255,255,255,0.20)";
                    context.lineWidth = 0.7;
                    context.save();
                    context.translate(centerX, centerY);
                    context.scale(0.43, 1);
                    context.beginPath();
                    context.arc(0, 0, radius, 0, Math.PI * 2);
                    context.stroke();
                    context.restore();
                    context.beginPath();
                    context.moveTo(centerX - radius, centerY);
                    context.lineTo(centerX + radius, centerY);
                    context.stroke();

                    let cityList = WorldClockService.cities || [];
                    context.strokeStyle = "#ffffff";
                    context.fillStyle = "#ffffff";
                    context.lineWidth = 0.9;
                    for (let index = 0; index < Math.min(cityList.length, 8); index++) {
                        let latitude = Number(cityList[index].latitude || 0);
                        let longitude = Number(cityList[index].longitude || 0);
                        let angle = (longitude - 90) * Math.PI / 180;
                        let targetRadius = radius * (0.38 + 0.14 * (1 - Math.min(90, Math.abs(latitude)) / 90));
                        let edgeX = centerX + Math.cos(angle) * radius * 0.82;
                        let edgeY = centerY + Math.sin(angle) * radius * 0.82;
                        let targetX = centerX + Math.cos(angle) * targetRadius;
                        let targetY = centerY + Math.sin(angle) * targetRadius - latitude / 90 * radius * 0.16;
                        context.beginPath();
                        context.moveTo(edgeX, edgeY);
                        context.lineTo(targetX, targetY);
                        context.stroke();
                        context.beginPath();
                        context.arc(targetX, targetY, 1.05, 0, Math.PI * 2);
                        context.fill();
                    }
                }
            }

            Connections {
                target: WorldClockService
                function onCitiesChanged() { earthIcon.requestPaint(); }
            }
        }

        Text {
            text: root.localTime
            font.family: ThemeBackend.fontFamily
            font.pixelSize: barWindow ? barWindow.s(root.isCompact ? 13 : 14) : (root.isCompact ? 13 : 14)
            font.weight: Font.Black
            color: root.isCompact ? Qt.lighter(ThemeBackend.text, 1.04) : ThemeBackend.text
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !root.togglePending
        onClicked: {
            if (!Caching.serpantinumDir || root.togglePending)
                return;
            root.togglePending = true;
            toggleGuard.restart();
            Quickshell.execDetached([
                "bash",
                Caching.serpantinumDir + "/scripts/qs_manager.sh",
                "toggle",
                "worldclock"
            ]);
        }
    }

    Timer {
        id: toggleGuard
        interval: 500
        repeat: false
        onTriggered: root.togglePending = false
    }

    Timer {
        running: barWindow && barWindow.isStartupReady
        interval: 120
        repeat: false
        onTriggered: root.showLayout = true
    }
}
