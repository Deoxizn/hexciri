import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The ASCII art Hexciri shows on the screensaver or the About screen, with
// the ways to change it: edit the text, make it from a picture, or go back
// to Hexciri's.
SettingsGroup {
    id: group
    property string which: "screensaver"
    readonly property string art: (backend.lists.branding || {})[which] || ""

    Rectangle {
        width: parent.width
        implicitHeight: Math.min(artText.implicitHeight, ui.s(220)) + ui.s(24)
        radius: theme.radius
        color: ui.normalFill
        border.width: 1
        border.color: ui.normalBorder
        clip: true
        // Art taller than the box scrolls inside it rather than losing its
        // top and bottom.
        Flickable {
            id: artView
            anchors.fill: parent
            anchors.margins: ui.s(12)
            contentWidth: width
            contentHeight: Math.max(height, artText.implicitHeight)
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ScrollBar.vertical: OmaScrollBar {}
            Text {
                id: artText
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(0, (artView.height - implicitHeight) / 2)
                text: group.art
                color: ui.accent
                font.family: ui.iconFont
                // Small enough that the widest line fits.
                font.pixelSize: Math.max(5, Math.min(ui.small, Math.floor(artView.width / Math.max(1, group.longest) / 0.6)))
                lineHeight: 1.0
                textFormat: Text.PlainText
                LayoutMirroring.enabled: false
            }
        }
    }
    readonly property int longest: art.split("\n").reduce((n, l) => Math.max(n, l.length), 0)

    SettingRow {
        label: ""
        OmaButton {
            text: qsTr("Edit Text…")
            onClicked: backend.act("branding.edit", [group.which])
        }
        OmaButton {
            text: qsTr("From a Picture…")
            onClicked: backend.act("branding.image", [group.which])
        }
        OmaButton {
            text: qsTr("Restore Hexciri's")
            bordered: false
            onClicked: backend.act("branding.reset", [group.which], ["branding"])
        }
    }
}
