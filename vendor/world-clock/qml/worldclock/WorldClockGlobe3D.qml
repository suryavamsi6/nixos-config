import QtQuick
import QtQuick3D
import ".."

Item {
    id: root

    property real yaw: -20
    property real pitch: 12
    property real cloudRotation: 0
    property real earthRadius: 180
    property string assetRoot: ""
    property var sunPosition: ({ latitude: 0, longitude: 0 })

    View3D {
        id: globeView
        anchors.fill: parent
        camera: camera
        renderMode: View3D.Inline
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            tonemapMode: SceneEnvironment.TonemapModeAces
        }

        PerspectiveCamera {
            id: camera
            z: 700
            clipNear: 10
            clipFar: 1500
            fieldOfView: 42
        }

        Node {
            id: presentationNode
            eulerRotation.x: root.pitch
            eulerRotation.y: root.yaw

            DirectionalLight {
                brightness: 2.15
                color: "#fff4df"
                ambientColor: "#17243a"
                castsShadow: false
                eulerRotation.x: -root.sunPosition.latitude
                eulerRotation.y: root.sunPosition.longitude
            }

            Model {
                source: "#Sphere"
                scale: Qt.vector3d(3.6, 3.6, 3.6)
                receivesShadows: false
                castsShadows: false
                materials: CustomMaterial {
                    shadingMode: CustomMaterial.Shaded
                    fragmentShader: root.assetRoot ? "file://" + root.assetRoot + "/shaders/earth.material.frag" : ""
                    property TextureInput dayMap: TextureInput {
                        texture: Texture {
                            source: root.assetRoot ? "file://" + root.assetRoot + "/earth-day.jpg" : ""
                            generateMipmaps: true
                        }
                    }
                    property TextureInput nightMap: TextureInput {
                        texture: Texture {
                            source: root.assetRoot ? "file://" + root.assetRoot + "/earth-night.png" : ""
                            generateMipmaps: true
                        }
                    }
                }
            }

            Model {
                source: "#Sphere"
                scale: Qt.vector3d(3.635, 3.635, 3.635)
                eulerRotation.y: root.cloudRotation
                receivesShadows: false
                castsShadows: false
                materials: PrincipledMaterial {
                    baseColor: "#dce8f4"
                    roughness: 1
                    metalness: 0
                    opacity: 0.30
                    alphaMode: PrincipledMaterial.Blend
                    opacityChannel: Material.R
                    opacityMap: Texture {
                        source: root.assetRoot ? "file://" + root.assetRoot + "/earth-clouds.jpg" : ""
                        generateMipmaps: true
                    }
                    cullMode: Material.BackFaceCulling
                }
            }

            Model {
                source: "#Sphere"
                scale: Qt.vector3d(3.72, 3.72, 3.72)
                receivesShadows: false
                castsShadows: false
                materials: CustomMaterial {
                    shadingMode: CustomMaterial.Shaded
                    fragmentShader: root.assetRoot ? "file://" + root.assetRoot + "/shaders/atmosphere.material.frag" : ""
                    sourceBlend: CustomMaterial.SrcAlpha
                    destinationBlend: CustomMaterial.OneMinusSrcAlpha
                    cullMode: Material.BackFaceCulling
                    property color atmosphereColor: ThemeBackend.sapphire
                    property real atmosphereStrength: 0.42
                }
            }
        }
    }
}
