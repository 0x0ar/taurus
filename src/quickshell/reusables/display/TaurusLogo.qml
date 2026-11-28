import QtQuick
import QtQuick.Effects
import "../../"

// Taurus logo painted in layers so it follows the active (Matugen) theme:
// a large broken cross-hatch that dissolves into fragments (two tones of the
// accent plus a darker scatter) and the theme text colour for the bull line.
Item {
    id: root

    property color accent: ThemeBackend.mauve
    property color lineColor: ThemeBackend.text
    property int sourcePx: 1024
    // The artwork is a landscape rectangle (300 x 190).
    readonly property real aspect: 190 / 300

    readonly property string assetsDir: "file://" + Caching.taurusDir + "/assets/"

    component Layer: Item {
        id: layer
        property string file
        property color tint
        anchors.fill: parent

        Image {
            id: img
            anchors.fill: parent
            source: root.assetsDir + layer.file
            sourceSize: Qt.size(root.sourcePx, Math.round(root.sourcePx * root.aspect))
            fillMode: Image.PreserveAspectFit
            smooth: true
            antialiasing: true
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            source: img
            brightness: 1.0
            colorization: 1.0
            colorizationColor: layer.tint
            autoPaddingEnabled: false
        }
    }

    Layer { file: "logo-base.svg";  tint: Qt.darker(root.accent, 2.6) }
    Layer { file: "logo-light.svg"; tint: Qt.darker(root.accent, 1.2) }
    Layer { file: "logo-dark.svg";  tint: Qt.darker(root.accent, 1.9) }
    Layer { file: "logo-bull.svg";  tint: root.lineColor }
}
