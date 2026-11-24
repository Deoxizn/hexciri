import QtQuick
import QtQuick.Controls

// A scroll bar that is there whenever there is more to see, thin at rest and
// wider under the pointer or while dragged, in the theme's foreground. The
// stock one stays hidden until something scrolls, so a page never said it
// had more below.
ScrollBar {
    id: bar
    readonly property bool needed: size < 1
    policy: needed ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    visible: needed
    minimumSize: 0.08
    padding: ui.s(2)
    // A wide target for the pointer around a thin thumb.
    implicitWidth: orientation === Qt.Vertical ? ui.s(12) : 0
    implicitHeight: orientation === Qt.Horizontal ? ui.s(12) : 0
    hoverEnabled: true

    contentItem: Item {
        implicitWidth: ui.s(8)
        implicitHeight: ui.s(8)
        Rectangle {
            readonly property bool wide: bar.hovered || bar.pressed
            anchors.right: bar.orientation === Qt.Vertical && !bar.mirrored ? parent.right : undefined
            anchors.left: bar.orientation === Qt.Vertical && bar.mirrored ? parent.left : undefined
            anchors.bottom: bar.orientation === Qt.Horizontal ? parent.bottom : undefined
            width: bar.orientation === Qt.Vertical ? (wide ? ui.s(8) : ui.s(4)) : parent.width
            height: bar.orientation === Qt.Vertical ? parent.height : (wide ? ui.s(8) : ui.s(4))
            radius: Math.min(width, height) / 2
            color: bar.pressed ? ui.alpha(ui.fg, 0.55) : wide ? ui.alpha(ui.fg, 0.4) : ui.alpha(ui.fg, 0.22)
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    background: Item {}
}
