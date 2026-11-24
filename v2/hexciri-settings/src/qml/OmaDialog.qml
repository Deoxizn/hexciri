import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A modal in the shell's style (qs.Ui ConfirmDialog): the theme background
// with the accent border, a bold title, the content, and its buttons.
Popup {
    id: dialog
    property string title
    property string acceptText: qsTr("OK")
    property string rejectText: qsTr("Cancel")
    property bool showReject: true
    property bool canAccept: true
    default property alias content: body.data
    signal accepted()
    signal rejected()

    function accept() { if (canAccept) { close(); accepted() } }
    function reject() { close(); rejected() }

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    padding: ui.s(18)
    // Kept inside the window: a long dialog scrolls its content between a
    // title and buttons that stay put.
    margins: ui.s(24)
    width: Math.min(parent ? parent.width - ui.s(48) : 400, Math.round(400 * ui.scale))
    closePolicy: Popup.CloseOnEscape

    Overlay.modal: Rectangle { color: ui.alpha(ui.bg, 0.6) }
    background: Rectangle {
        color: ui.bg
        border.color: ui.accent
        border.width: 1
        radius: theme.radius
    }

    contentItem: ColumnLayout {
        spacing: ui.s(14)
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        Text {
            id: titleText
            Layout.fillWidth: true
            text: dialog.title
            horizontalAlignment: Text.AlignLeft
            color: ui.fg
            font.family: ui.font
            font.pixelSize: ui.title
            font.bold: true
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        Flickable {
            id: bodyFlick
            readonly property real room: (dialog.parent ? dialog.parent.height : 600) - dialog.margins * 2
                - dialog.topPadding - dialog.bottomPadding - titleText.implicitHeight - buttons.implicitHeight - ui.s(14) * 2
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(body.implicitHeight, Math.max(ui.s(80), room))
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: contentHeight > height
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: OmaScrollBar {}

            ColumnLayout {
                id: body
                width: bodyFlick.width - (bodyFlick.interactive ? ui.s(14) : 0)
                spacing: ui.s(10)
            }
        }
        // Tabbing to a field below the fold brings it into view.
        Connections {
            target: dialog.opened ? win : null
            function onActiveFocusItemChanged() {
                const item = win.activeFocusItem
                if (!item || !bodyFlick.interactive) return
                let inside = false
                for (let p = item; p; p = p.parent) if (p === body) { inside = true; break }
                if (!inside) return
                const top = item.mapToItem(body, 0, 0).y
                const bottom = top + item.height
                if (top < bodyFlick.contentY) bodyFlick.contentY = Math.max(0, top - ui.s(8))
                else if (bottom > bodyFlick.contentY + bodyFlick.height)
                    bodyFlick.contentY = Math.min(bodyFlick.contentHeight - bodyFlick.height, bottom - bodyFlick.height + ui.s(8))
            }
        }
        RowLayout {
            id: buttons
            Layout.alignment: Qt.AlignRight
            spacing: ui.s(8)
            OmaButton {
                visible: dialog.showReject
                text: dialog.rejectText
                onClicked: dialog.reject()
            }
            OmaButton {
                text: dialog.acceptText
                highlighted: true
                enabled: dialog.canAccept
                onClicked: dialog.accept()
            }
        }
    }
}
