import QtQuick
import QtQuick3D
import QtQuick.Controls
import "../"

Item {
    id: root
    property var clocks: []
    property int selectedIndex: 0
    property bool active: visible
    property real globeScale: 1.0
    signal markerSelected(int index)

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: Qt.alpha(ThemeBackend.crust, 0.34)
        border.color: Qt.alpha(ThemeBackend.blue, 0.28)
        border.width: 1
    }

    View3D {
        id: view
        anchors.fill: parent
        anchors.margins: 8
        renderMode: View3D.Offscreen
        environment: SceneEnvironment { clearColor: "transparent"; backgroundMode: SceneEnvironment.Color }
        PerspectiveCamera { id: camera; z: 145 / root.globeScale; clipNear: 1; clipFar: 500 }
        DirectionalLight { eulerRotation: Qt.vector3d(-28, -42, 0); color: "#dce9ff"; brightness: 1.25 }
        PointLight { position: Qt.vector3d(-80, 55, 120); color: ThemeBackend.mauve; brightness: 0.35 }
        Node {
            id: globeNode
            eulerRotation: Qt.vector3d(0, root.active ? root.idleRotation : 0, 0)
            Model {
                source: "#Sphere"
                materials: [ PrincipledMaterial { baseColorMap: Texture { source: "earth-land.svg"; generateMipmaps: true }; roughness: 0.92; metalness: 0.02 } ]
            }
            Model {
                source: "#Sphere"
                scale: Qt.vector3d(1.035, 1.035, 1.035)
                materials: [ PrincipledMaterial { baseColor: Qt.alpha(ThemeBackend.blue, 0.08); opacity: 0.10 } ]
            }
            Repeater3D {
                model: root.clocks
                delegate: Node {
                    property int clockIndex: index
                    position: {
                        const lat = (Number(modelData.lat) || 0) * Math.PI / 180;
                        const lon = (Number(modelData.lon) || 0) * Math.PI / 180;
                        return Qt.vector3d(52 * Math.cos(lat) * Math.sin(lon), 52 * Math.sin(lat), 52 * Math.cos(lat) * Math.cos(lon));
                    }
                    Model {
                        source: "#Sphere"
                        scale: {
                            const size = clockIndex === root.selectedIndex ? 0.18 : 0.11;
                            return Qt.vector3d(size, size, size);
                        }
                        materials: [ PrincipledMaterial { baseColor: clockIndex === root.selectedIndex ? ThemeBackend.peach : ThemeBackend.teal; emissiveFactor: Qt.vector3d(0.2, 0.3, 0.4) } ]
                    }
                }
            }
        }
    }

    property real idleRotation: 0
    NumberAnimation on idleRotation { from: 0; to: 360; duration: 90000; loops: Animation.Infinite; running: root.active }
    WheelHandler { target: root; onWheel: event => root.globeScale = Math.max(0.72, Math.min(1.45, root.globeScale + event.angleDelta.y / 2400)) }
    DragHandler { target: null; enabled: root.active; onTranslationChanged: globeNode.eulerRotation = Qt.vector3d(globeNode.eulerRotation.x - translation.y * 0.35, globeNode.eulerRotation.y + translation.x * 0.35, 0) }
}
