import QtQuick
import QtQuick.Layouts
import ".."
import "WorldClockMath.js" as ClockMath

Item {
    id: root

    property bool active: false
    property var cities: []
    property var clocks: []
    property string selectedCityId: ""
    signal citySelected(string cityId)

    property real yaw: -20
    property real pitch: 12
    property real velocityYaw: 0
    property real velocityPitch: 0
    property real idleBlend: 1
    property string interactionState: "idle"
    property double lastFrameTime: Date.now()
    property var markerLayout: []

    readonly property bool autoRotate: WorldClockService.globe.autoRotate
    readonly property real rotationSpeed: Number(WorldClockService.globe.rotationSpeed || 2.5)
    readonly property real globeRadius: Math.max(1, Math.min(width, height) * 0.355)
    readonly property real globeCenterX: width / 2
    readonly property real globeCenterY: height / 2
    readonly property int markerWidth: 142
    readonly property int markerHeight: 38
    readonly property var landmasses: [
        [[72, -168], [70, -140], [59, -124], [50, -130], [42, -124], [31, -116], [22, -106], [18, -96], [9, -82], [18, -76], [30, -81], [42, -69], [51, -56], [61, -64], [70, -82], [76, -108]],
        [[12, -81], [6, -76], [-5, -80], [-18, -74], [-34, -71], [-55, -68], [-52, -55], [-34, -48], [-18, -39], [-5, -35], [6, -50], [12, -65]],
        [[36, -10], [43, -5], [51, 2], [59, 10], [70, 28], [65, 40], [55, 40], [47, 31], [39, 21]],
        [[37, -17], [37, 11], [31, 33], [12, 45], [-12, 40], [-35, 18], [-34, 1], [-17, -12], [5, -17], [20, -15]],
        [[70, 28], [75, 78], [69, 121], [61, 151], [49, 160], [40, 140], [21, 122], [6, 105], [10, 79], [25, 59], [40, 45], [55, 40]],
        [[-11, 113], [-18, 122], [-35, 116], [-44, 135], [-38, 153], [-24, 153], [-11, 142]],
        [[83, -73], [77, -18], [60, -43], [59, -61], [72, -74]],
        [[46, 130], [44, 146], [35, 141], [31, 130]],
        [[8, 95], [2, 105], [-7, 108], [-9, 116], [0, 120], [8, 112]]
    ]

    function clockFor(cityId) {
        for (let index = 0; index < clocks.length; index++) {
            if (clocks[index].id === cityId)
                return clocks[index];
        }
        return null;
    }

    function beginResume() {
        interactionState = "idle";
        idleBlend = 0;
        resumeAnimation.restart();
    }

    function advanceFrame(deltaSeconds) {
        if (interactionState === "inertia") {
            yaw += velocityYaw * deltaSeconds;
            pitch = ClockMath.clamp(pitch + velocityPitch * deltaSeconds, -70, 70);
            let decay = Math.pow(0.045, deltaSeconds);
            velocityYaw *= decay;
            velocityPitch *= decay;
            if (Math.abs(velocityYaw) + Math.abs(velocityPitch) < 0.8) {
                velocityYaw = 0;
                velocityPitch = 0;
                beginResume();
            }
        } else if (interactionState === "idle" && autoRotate) {
            yaw += rotationSpeed * idleBlend * deltaSeconds;
        }
        if (Math.abs(yaw) > 720)
            yaw = ClockMath.normalizeLongitude(yaw);
    }

    function focusSelectedCity() {
        if (!active || interactionState === "drag")
            return;
        let city = null;
        for (let index = 0; index < cities.length; index++) {
            if (cities[index].id === selectedCityId) {
                city = cities[index];
                break;
            }
        }
        if (!city || city.latitude === undefined || city.longitude === undefined)
            return;
        interactionState = "focus";
        velocityYaw = 0;
        velocityPitch = 0;
        resumeAnimation.stop();
        idleBlend = 0;
        yawFocus.from = yaw;
        yawFocus.to = ClockMath.nearestAngle(yaw, -Number(city.longitude));
        pitchFocus.from = pitch;
        pitchFocus.to = ClockMath.clamp(Number(city.latitude), -62, 62);
        focusAnimation.restart();
    }

    function projectCoordinate(latitude, longitude) {
        let lat = Number(latitude) * Math.PI / 180;
        let lon = Number(longitude) * Math.PI / 180;
        let centerLat = Number(pitch) * Math.PI / 180;
        let centerLon = -Number(yaw) * Math.PI / 180;
        let deltaLon = lon - centerLon;
        let cosLat = Math.cos(lat);
        let depth = Math.sin(centerLat) * Math.sin(lat)
            + Math.cos(centerLat) * cosLat * Math.cos(deltaLon);
        let projectedX = cosLat * Math.sin(deltaLon);
        let projectedY = Math.cos(centerLat) * Math.sin(lat)
            - Math.sin(centerLat) * cosLat * Math.cos(deltaLon);
        return {
            x: globeCenterX + globeRadius * projectedX,
            y: globeCenterY - globeRadius * projectedY,
            visible: depth > 0.025,
            depth: depth
        };
    }

    function settleLabels(entries) {
        let groups = [[], []];
        for (let index = 0; index < entries.length; index++) {
            if (entries[index].visible)
                groups[entries[index].side > 0 ? 1 : 0].push(entries[index]);
        }
        for (let sideIndex = 0; sideIndex < groups.length; sideIndex++) {
            let group = groups[sideIndex];
            group.sort(function(left, right) { return left.y - right.y; });
            let cursor = 4;
            for (let index = 0; index < group.length; index++) {
                group[index].y = Math.max(group[index].y, cursor);
                cursor = group[index].y + markerHeight + 5;
            }
            let overflow = cursor - 5 - (height - 4);
            if (overflow > 0) {
                for (let index = 0; index < group.length; index++)
                    group[index].y = Math.max(4, group[index].y - overflow);
            }
            for (let index = group.length - 2; index >= 0; index--)
                group[index].y = Math.min(group[index].y, group[index + 1].y - markerHeight - 5);
        }
    }

    function updateMarkerLayout() {
        let layout = [];
        for (let index = 0; index < cities.length; index++) {
            let city = cities[index];
            let latitude = Number(city.latitude);
            let longitude = Number(city.longitude);
            if (!isFinite(latitude) || !isFinite(longitude)) {
                layout.push({ visible: false, x: 0, y: 0, pointX: 0, pointY: 0, side: 1 });
                continue;
            }
            let point = projectCoordinate(latitude, longitude);
            let side = point.x >= globeCenterX ? 1 : -1;
            let labelX = side > 0
                ? Math.min(width - markerWidth - 4, point.x + 24)
                : Math.max(4, point.x - markerWidth - 24);
            layout.push({
                visible: point.visible,
                x: labelX,
                y: ClockMath.clamp(point.y - markerHeight / 2, 4, height - markerHeight - 4),
                pointX: point.x,
                pointY: point.y,
                side: side,
                depth: point.depth
            });
        }
        settleLabels(layout);
        for (let index = 0; index < layout.length; index++) {
            let placement = layout[index];
            placement.anchorX = placement.side > 0 ? placement.x : placement.x + markerWidth;
            placement.anchorY = placement.y + markerHeight / 2;
        }
        markerLayout = layout;
        globeCanvas.requestPaint();
    }

    function drawGeoPath(context, coordinates) {
        let drawing = false;
        context.beginPath();
        for (let index = 0; index < coordinates.length; index++) {
            let point = projectCoordinate(coordinates[index][0], coordinates[index][1]);
            if (!point.visible) {
                drawing = false;
                continue;
            }
            if (!drawing) {
                context.moveTo(point.x, point.y);
                drawing = true;
            } else {
                context.lineTo(point.x, point.y);
            }
        }
        context.stroke();
    }

    function drawLandmass(context, coordinates) {
        let points = [];
        for (let index = 0; index < coordinates.length; index++) {
            let point = projectCoordinate(coordinates[index][0], coordinates[index][1]);
            if (point.visible)
                points.push(point);
        }
        if (points.length < 3)
            return;
        context.beginPath();
        context.moveTo(points[0].x, points[0].y);
        for (let index = 1; index < points.length; index++)
            context.lineTo(points[index].x, points[index].y);
        context.closePath();
        context.fill();
        context.stroke();
    }

    function paintGlobe(context) {
        let centerX = globeCenterX;
        let centerY = globeCenterY;
        let radius = globeRadius;

        context.clearRect(0, 0, width, height);

        context.fillStyle = "rgba(255,255,255,0.025)";
        context.beginPath();
        context.arc(centerX, centerY, radius * 1.12, 0, Math.PI * 2);
        context.fill();

        context.save();
        context.beginPath();
        context.arc(centerX, centerY, radius, 0, Math.PI * 2);
        context.clip();
        context.fillStyle = "#05070b";
        context.fillRect(centerX - radius, centerY - radius, radius * 2, radius * 2);

        context.fillStyle = "#2b3038";
        context.strokeStyle = "rgba(255,255,255,0.24)";
        context.lineWidth = 1;
        for (let index = 0; index < landmasses.length; index++)
            drawLandmass(context, landmasses[index]);

        context.fillStyle = "rgba(255,255,255,0.035)";
        context.beginPath();
        context.arc(centerX - radius * 0.28, centerY - radius * 0.3, radius * 0.68, 0, Math.PI * 2);
        context.fill();

        context.strokeStyle = "rgba(255,255,255,0.13)";
        context.lineWidth = 1;
        for (let latitude = -60; latitude <= 60; latitude += 30) {
            let latitudeLine = [];
            for (let longitude = -180; longitude <= 180; longitude += 5)
                latitudeLine.push([latitude, longitude]);
            drawGeoPath(context, latitudeLine);
        }
        for (let longitude = -150; longitude <= 180; longitude += 30) {
            let longitudeLine = [];
            for (let latitude = -85; latitude <= 85; latitude += 5)
                longitudeLine.push([latitude, longitude]);
            drawGeoPath(context, longitudeLine);
        }
        context.restore();

        context.strokeStyle = "rgba(255,255,255,0.48)";
        context.lineWidth = 1.4;
        context.beginPath();
        context.arc(centerX, centerY, radius, 0, Math.PI * 2);
        context.stroke();

        for (let index = 0; index < markerLayout.length; index++) {
            let placement = markerLayout[index];
            if (!placement.visible)
                continue;
            let selected = cities[index] && cities[index].id === selectedCityId;
            context.strokeStyle = selected ? "rgba(255,255,255,1)" : "rgba(255,255,255,0.76)";
            context.fillStyle = "#ffffff";
            context.lineWidth = selected ? 2 : 1.35;
            context.beginPath();
            context.moveTo(placement.pointX, placement.pointY);
            context.lineTo(placement.pointX + placement.side * 12, placement.pointY);
            context.lineTo(placement.anchorX, placement.anchorY);
            context.stroke();
            context.beginPath();
            context.arc(placement.pointX, placement.pointY, selected ? 4 : 3, 0, Math.PI * 2);
            context.fill();
            context.strokeStyle = "rgba(0,0,0,0.9)";
            context.lineWidth = 1;
            context.stroke();
        }
    }

    onSelectedCityIdChanged: focusSelectedCity()
    onCitiesChanged: Qt.callLater(updateMarkerLayout)
    onClocksChanged: Qt.callLater(updateMarkerLayout)
    onWidthChanged: Qt.callLater(updateMarkerLayout)
    onHeightChanged: Qt.callLater(updateMarkerLayout)
    onActiveChanged: {
        if (active) {
            lastFrameTime = Date.now();
            Qt.callLater(function() {
                root.focusSelectedCity();
                root.updateMarkerLayout();
            });
        } else {
            focusAnimation.stop();
            resumeAnimation.stop();
            interactionState = "idle";
            velocityYaw = 0;
            velocityPitch = 0;
        }
    }

    Canvas {
        id: globeCanvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image
        onPaint: root.paintGlobe(getContext("2d"))
        Component.onCompleted: root.updateMarkerLayout()
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.active && root.cities.length > 0
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real previousX: 0
        property real previousY: 0
        property double previousTime: 0

        onPressed: mouse => {
            focusAnimation.stop();
            resumeAnimation.stop();
            root.interactionState = "drag";
            root.idleBlend = 0;
            root.velocityYaw = 0;
            root.velocityPitch = 0;
            previousX = mouse.x;
            previousY = mouse.y;
            previousTime = Date.now();
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            let now = Date.now();
            let elapsed = Math.max(8, now - previousTime) / 1000;
            let yawDelta = (mouse.x - previousX) * 0.32;
            let pitchDelta = (mouse.y - previousY) * 0.27;
            root.yaw += yawDelta;
            root.pitch = ClockMath.clamp(root.pitch + pitchDelta, -70, 70);
            root.velocityYaw = yawDelta / elapsed;
            root.velocityPitch = pitchDelta / elapsed;
            previousX = mouse.x;
            previousY = mouse.y;
            previousTime = now;
            root.updateMarkerLayout();
        }
        onReleased: {
            root.interactionState = "inertia";
            if (Math.abs(root.velocityYaw) + Math.abs(root.velocityPitch) < 0.8)
                root.beginResume();
        }
        onCanceled: root.beginResume()
    }

    Repeater {
        model: root.cities
        delegate: Rectangle {
            id: labelCard
            required property var modelData
            required property int index
            readonly property var placement: root.markerLayout[index] || ({ visible: false, x: 0, y: 0 })
            readonly property var clock: root.clockFor(modelData.id)
            readonly property bool selected: modelData.id === root.selectedCityId

            x: placement.x
            y: placement.y
            width: root.markerWidth
            height: root.markerHeight
            visible: placement.visible
            radius: height / 2
            color: selected ? "#f4f4f5" : "#090b10"
            border.width: 1
            border.color: selected ? "#ffffff" : "#8b8f98"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 10
                spacing: 7
                Rectangle {
                    width: 7
                    height: 7
                    radius: 4
                    color: labelCard.selected ? "#090b10" : "#ffffff"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -1
                    Text {
                        Layout.fillWidth: true
                        text: modelData.label || modelData.place
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: labelCard.selected ? "#090b10" : "#ffffff"
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: labelCard.clock ? labelCard.clock.time + " · " + labelCard.clock.abbreviation : modelData.timezone
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 8
                        color: labelCard.selected ? "#3f3f46" : "#b8bbc3"
                        elide: Text.ElideRight
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.citySelected(modelData.id)
            }
        }
    }

    ParallelAnimation {
        id: focusAnimation
        NumberAnimation {
            id: yawFocus
            target: root
            property: "yaw"
            duration: 850
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            id: pitchFocus
            target: root
            property: "pitch"
            duration: 850
            easing.type: Easing.InOutCubic
        }
        onFinished: root.beginResume()
    }

    NumberAnimation {
        id: resumeAnimation
        target: root
        property: "idleBlend"
        from: 0
        to: 1
        duration: 1400
        easing.type: Easing.InOutCubic
    }

    Timer {
        interval: 33
        repeat: true
        running: root.active
        onTriggered: {
            let now = Date.now();
            let delta = Math.min(0.06, Math.max(0.001, (now - root.lastFrameTime) / 1000));
            root.lastFrameTime = now;
            root.advanceFrame(delta);
            root.updateMarkerLayout();
        }
    }
}
