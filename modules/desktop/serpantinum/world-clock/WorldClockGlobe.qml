import QtQuick
import "../"

Item {
    id: root

    property var clocks: []
    property int selectedIndex: 0
    property bool active: visible
    property real yaw: -18
    property real pitch: -8
    property real globeScale: 1.0
    property bool dragging: false
    property point pressPoint: Qt.point(0, 0)
    property point lastPoint: Qt.point(0, 0)

    signal markerSelected(int index)

    function project(latDegrees, lonDegrees) {
        const lat = Number(latDegrees || 0) * Math.PI / 180
        const lon = Number(lonDegrees || 0) * Math.PI / 180
        const yawRadians = root.yaw * Math.PI / 180
        const pitchRadians = root.pitch * Math.PI / 180
        const cosLat = Math.cos(lat)
        const x = cosLat * Math.sin(lon)
        const y = Math.sin(lat)
        const z = cosLat * Math.cos(lon)
        const rotatedX = x * Math.cos(yawRadians) + z * Math.sin(yawRadians)
        const rotatedZ = -x * Math.sin(yawRadians) + z * Math.cos(yawRadians)
        const rotatedY = y * Math.cos(pitchRadians) - rotatedZ * Math.sin(pitchRadians)
        const depth = y * Math.sin(pitchRadians) + rotatedZ * Math.cos(pitchRadians)
        const radius = Math.min(globeCanvas.width, globeCanvas.height) * 0.41 * root.globeScale
        return {
            x: globeCanvas.width / 2 + radius * rotatedX,
            y: globeCanvas.height / 2 - radius * rotatedY,
            depth: depth,
            radius: radius
        }
    }

    function markerAt(x, y) {
        let nearest = -1
        let nearestDistance = 18
        for (let i = 0; i < root.clocks.length; i++) {
            const point = root.project(root.clocks[i].lat, root.clocks[i].lon)
            if (point.depth <= 0) continue
            const distance = Math.hypot(point.x - x, point.y - y)
            if (distance < nearestDistance) {
                nearest = i
                nearestDistance = distance
            }
        }
        return nearest
    }

    onYawChanged: globeCanvas.requestPaint()
    onPitchChanged: globeCanvas.requestPaint()
    onGlobeScaleChanged: globeCanvas.requestPaint()
    onClocksChanged: globeCanvas.requestPaint()
    onSelectedIndexChanged: globeCanvas.requestPaint()

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: Qt.alpha(ThemeBackend.crust, 0.34)
        border.color: Qt.alpha(ThemeBackend.blue, 0.28)
        border.width: 1
    }

    Canvas {
        id: globeCanvas
        anchors.fill: parent
        anchors.margins: 8
        antialiasing: true

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onImageLoaded: requestPaint()
        Component.onCompleted: loadImage("earth-land.svg")

        onPaint: {
            const ctx = getContext("2d")
            const width = globeCanvas.width
            const height = globeCanvas.height
            ctx.clearRect(0, 0, width, height)

            const centerX = width / 2
            const centerY = height / 2
            const radius = Math.min(width, height) * 0.41 * root.globeScale
            if (radius <= 1) return

            ctx.save()
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
            ctx.clip()

            ctx.fillStyle = "#10203b"
            ctx.fillRect(centerX - radius, centerY - radius, radius * 2, radius * 2)

            if (isImageLoaded("earth-land.svg")) {
                const textureWidth = radius * 4
                const textureHeight = radius * 2
                let textureX = centerX - textureWidth / 2 + ((root.yaw % 360) / 360) * textureWidth
                const textureY = centerY - textureHeight / 2 + root.pitch * radius / 120
                while (textureX > centerX - radius) textureX -= textureWidth
                for (let copy = 0; copy < 3; copy++) {
                    ctx.drawImage("earth-land.svg", textureX + copy * textureWidth, textureY, textureWidth, textureHeight)
                }
            }

            const shade = ctx.createRadialGradient(
                centerX - radius * 0.35,
                centerY - radius * 0.4,
                radius * 0.08,
                centerX,
                centerY,
                radius
            )
            shade.addColorStop(0, "rgba(166, 227, 255, 0.22)")
            shade.addColorStop(0.55, "rgba(30, 62, 95, 0.06)")
            shade.addColorStop(1, "rgba(0, 4, 18, 0.72)")
            ctx.fillStyle = shade
            ctx.fillRect(centerX - radius, centerY - radius, radius * 2, radius * 2)
            ctx.restore()

            function drawGridLine(points) {
                let drawing = false
                ctx.beginPath()
                for (let i = 0; i < points.length; i++) {
                    const point = points[i]
                    if (point.depth <= 0) {
                        drawing = false
                        continue
                    }
                    if (!drawing) {
                        ctx.moveTo(point.x, point.y)
                        drawing = true
                    } else {
                        ctx.lineTo(point.x, point.y)
                    }
                }
                ctx.stroke()
            }

            ctx.save()
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
            ctx.clip()
            ctx.strokeStyle = "rgba(109, 213, 237, 0.20)"
            ctx.lineWidth = 1

            for (let latitude = -60; latitude <= 60; latitude += 30) {
                let latitudePoints = []
                for (let longitude = -180; longitude <= 180; longitude += 4) {
                    latitudePoints.push(root.project(latitude, longitude))
                }
                drawGridLine(latitudePoints)
            }
            for (let longitude = -150; longitude <= 180; longitude += 30) {
                let longitudePoints = []
                for (let latitude = -90; latitude <= 90; latitude += 3) {
                    longitudePoints.push(root.project(latitude, longitude))
                }
                drawGridLine(longitudePoints)
            }
            ctx.restore()

            ctx.strokeStyle = "rgba(137, 220, 255, 0.72)"
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
            ctx.stroke()

            for (let i = 0; i < root.clocks.length; i++) {
                const marker = root.project(root.clocks[i].lat, root.clocks[i].lon)
                if (marker.depth <= 0) continue
                const selected = i === root.selectedIndex
                const markerRadius = selected ? 7 : 4.5
                ctx.shadowBlur = selected ? 16 : 8
                ctx.shadowColor = selected ? "#fab387" : "#94e2d5"
                ctx.fillStyle = selected ? "#fab387" : "#94e2d5"
                ctx.beginPath()
                ctx.arc(marker.x, marker.y, markerRadius, 0, Math.PI * 2)
                ctx.fill()
                ctx.shadowBlur = 0
            }
        }
    }

    MouseArea {
        anchors.fill: globeCanvas
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: mouse => {
            root.dragging = true
            root.pressPoint = Qt.point(mouse.x, mouse.y)
            root.lastPoint = Qt.point(mouse.x, mouse.y)
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            const deltaX = mouse.x - root.lastPoint.x
            const deltaY = mouse.y - root.lastPoint.y
            root.yaw = (root.yaw + deltaX * 0.45) % 360
            root.pitch = Math.max(-70, Math.min(70, root.pitch - deltaY * 0.35))
            root.lastPoint = Qt.point(mouse.x, mouse.y)
        }
        onReleased: mouse => {
            root.dragging = false
            if (Math.hypot(mouse.x - root.pressPoint.x, mouse.y - root.pressPoint.y) < 7) {
                const marker = root.markerAt(mouse.x, mouse.y)
                if (marker >= 0) root.markerSelected(marker)
            }
        }
        onCanceled: root.dragging = false
        onWheel: wheel => {
            const step = wheel.angleDelta.y > 0 ? 0.08 : -0.08
            root.globeScale = Math.max(0.72, Math.min(1.32, root.globeScale + step))
            wheel.accepted = true
        }
    }

    Timer {
        interval: 33
        repeat: true
        running: root.active && !root.dragging
        onTriggered: root.yaw = (root.yaw + 0.132) % 360
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        spacing: 2
        visible: root.clocks.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.clocks.length
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.clocks[root.selectedIndex] ? root.clocks[root.selectedIndex].label : ""
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.bold: true
            font.pixelSize: 13
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "DRAG TO ROTATE  ·  SCROLL TO ZOOM"
            color: ThemeBackend.overlay1
            font.family: ThemeBackend.fontFamily
            font.pixelSize: 9
        }
    }
}
