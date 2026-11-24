import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A pane's scrolling page. It opens with a hero like the shell's panels:
// the glyph, the name in bold, an uppercase line under it, and the pane's
// main switch on the far side (Wi-Fi, Bluetooth).
ScrollView {
    id: page
    property string pane
    property string title
    property string glyph
    property string tagline
    property string description
    property string heroSetting
    // Lists to load when the page opens, and how often to refresh live data.
    property var lists: []
    // Settings from other panes this page also shows.
    property var settings: []
    property int pollMs: 0
    // The pane whose settings Restore Defaults puts back to Hexciri's.
    property string resetPane: ""
    // The config files this page's settings live in, by their key in the
    // backend's table, the main one first. They are offered at the bottom
    // to open in the person's editor, and Ctrl+E opens the first.
    property var configFiles: []
    readonly property var shownConfigFiles: configFiles.length === 0 ? []
        : configFiles.map(k => (backend.lists.configFiles || []).find(f => f.key === k)).filter(f => f && f.exists)
    default property alias content: column.data
    // A list the page shows that hasn't arrived the first time yet.
    readonly property bool loading: lists.some(l => backend.lists[l] === undefined)

    function reload() {
        if (pane.length > 0)
            backend.refreshPane(pane)
        for (const list of lists)
            backend.load(list)
        for (const id of settings)
            backend.refresh(id)
        if (configFiles.length > 0)
            backend.load("configFiles")
    }

    // Opens the page's main config file; false when it has none.
    function openConfig() {
        if (shownConfigFiles.length === 0)
            return false
        backend.act("edit", [shownConfigFiles[0].key])
        return true
    }

    // Scrolls so `item` shows, a little below the top. Rows can still be
    // settling (a list arriving, a group opening), so it looks once more
    // after a moment.
    function reveal(item) {
        revealTarget = item
        placeReveal()
        revealAgain.restart()
    }
    property Item revealTarget: null
    function placeReveal() {
        if (!revealTarget) return
        const y = revealTarget.mapToItem(outer, 0, 0).y
        scrollTo(Math.max(0, Math.min(y - ui.s(60), flick.contentHeight - flick.height)), false)
    }
    Timer { id: revealAgain; interval: 250; onTriggered: { page.placeReveal(); page.revealTarget = null } }

    readonly property Flickable flick: page.contentItem
    readonly property real maxY: Math.max(0, flick.contentHeight - flick.height)
    function scrollTo(y, animated) {
        y = Math.max(0, Math.min(y, maxY))
        scrollAnimation.stop()
        if (animated) {
            scrollAnimation.to = y
            scrollAnimation.start()
        } else {
            flick.contentY = y
        }
    }
    NumberAnimation {
        id: scrollAnimation
        target: page.flick
        property: "contentY"
        duration: 160
        easing.type: Easing.OutCubic
    }

    // Where to scroll back to, coming back to the page; it waits for the
    // page's lists to arrive and grow it that far.
    property real restoreY: -1
    onContentHeightChanged: placeRestore()
    function placeRestore() {
        if (restoreY < 0) return
        flick.contentY = Math.min(restoreY, maxY)
        if (maxY >= restoreY) restoreY = -1
    }
    onRestoreYChanged: if (restoreY >= 0) Qt.callLater(placeRestore)
    Timer { running: page.restoreY >= 0; interval: 1500; onTriggered: page.restoreY = -1 }

    // Scrolls only as far as it takes for `item` to show whole, with a
    // little room around it, so moving through a page with Tab never leaves
    // the focus out of sight.
    function ensureVisible(item) {
        const top = item.mapToItem(outer, 0, 0).y
        const bottom = top + item.height
        const room = ui.s(24)
        if (top - room < flick.contentY)
            scrollTo(top - room, true)
        else if (bottom + room > flick.contentY + flick.height)
            scrollTo(Math.min(top - room, bottom + room - flick.height), true)
    }
    function contains(item) {
        for (let p = item; p; p = p.parent)
            if (p === outer) return true
        return false
    }
    Connections {
        target: win
        function onActiveFocusItemChanged() {
            const item = win.activeFocusItem
            if (item && item !== page && page.contains(item))
                page.ensureVisible(item)
        }
    }
    // Paging through with the keyboard, when the focused control has no use
    // for the key itself.
    Keys.onPressed: event => {
        const step = flick.height - ui.s(48)
        if (event.key === Qt.Key_PageDown) scrollTo(flick.contentY + step, true)
        else if (event.key === Qt.Key_PageUp) scrollTo(flick.contentY - step, true)
        else if (event.key === Qt.Key_Home && event.modifiers & Qt.ControlModifier) scrollTo(0, true)
        else if (event.key === Qt.Key_End && event.modifiers & Qt.ControlModifier) scrollTo(maxY, true)
        else return
        event.accepted = true
    }

    // Always there when the page is longer than the window, so it says
    // there is more below; it sits in the page's margin, clear of the rows.
    ScrollBar.vertical: OmaScrollBar {
        parent: page
        x: page.mirrored ? 0 : page.width - width
        y: page.topPadding
        height: page.availableHeight
    }
    Component.onCompleted: {
        flick.boundsBehavior = Flickable.StopAtBounds
        reload()
    }

    contentWidth: availableWidth
    contentHeight: outer.implicitHeight + ui.s(40)
    clip: true

    // Changes made elsewhere arrive on their own (Backend watches the files
    // and events behind each setting), so coming back to the window reads
    // everything again only now and then, as a backstop.
    property double reloadedAt: Date.now()
    Connections {
        target: win
        function onActiveChanged() {
            if (win.active && Date.now() - page.reloadedAt > 10000) {
                page.reloadedAt = Date.now()
                page.reload()
            }
        }
    }
    Timer {
        interval: Math.max(1000, page.pollMs)
        running: page.pollMs > 0 && win.active
        repeat: true
        onTriggered: page.reload()
    }
    // What nothing announces (Night Light, brightness, radios), read again
    // every few seconds while the window is in front.
    Timer {
        interval: 3000
        running: page.pane.length > 0 && win.active
        repeat: true
        onTriggered: backend.refreshLive(page.pane)
    }

    ColumnLayout {
      id: outer
      width: Math.min(page.availableWidth - (page.availableWidth < ui.s(500) ? ui.s(28) : ui.s(56)), Math.round(640 * ui.scale))
      x: (page.availableWidth - width) / 2
      spacing: ui.s(18)

      ColumnLayout {
        id: column
        Layout.fillWidth: true
        spacing: ui.s(18)

        Item { implicitHeight: ui.s(6) }

        RowLayout {
            visible: page.glyph.length > 0
            Layout.fillWidth: true
            spacing: ui.s(14)

            PaneIcon {
                glyph: page.glyph
                size: ui.display
                Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: ui.s(2)
                Text {
                    text: page.title
                    horizontalAlignment: Text.AlignLeft
                    color: ui.fg
                    font.family: ui.font
                    font.pixelSize: ui.title
                    font.bold: true
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                }
                Text {
                    visible: page.tagline.length > 0
                    text: page.tagline.toLocaleUpperCase(Qt.locale())
                    horizontalAlignment: Text.AlignLeft
                    color: ui.muted
                    font.family: ui.font
                    font.pixelSize: ui.caption
                    font.bold: true
                    // Spacing letters apart breaks up joined scripts like Arabic.
                    font.letterSpacing: Qt.application.layoutDirection === Qt.RightToLeft ? 0 : 1
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                }
            }
            Spinner { running: page.heroSetting.length > 0 && backend.busy.indexOf(page.heroSetting) >= 0 }
            OmaToggle {
                visible: page.heroSetting.length > 0
                checked: !!backend.values[page.heroSetting]
                interactive: backend.values[page.heroSetting] !== undefined
                onToggled: backend.set(page.heroSetting, !backend.values[page.heroSetting])
                Accessible.role: Accessible.CheckBox
                Accessible.name: page.title
                Accessible.checked: checked
            }
        }

        Text {
            visible: page.description.length > 0
            Layout.fillWidth: true
            Layout.topMargin: -ui.s(6)
            text: page.description
            horizontalAlignment: Text.AlignLeft
            color: ui.muted2
            font.family: ui.font
            font.pixelSize: ui.small
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        // While what the page lists is still on its way.
        RowLayout {
            visible: page.loading
            Layout.fillWidth: true
            spacing: ui.s(8)
            Spinner { running: page.loading }
            Text {
                Layout.fillWidth: true
                text: qsTr("Loading…")
                horizontalAlignment: Text.AlignLeft
                color: ui.muted
                font.family: ui.font
                font.pixelSize: ui.small
                textFormat: Text.PlainText
            }
        }
    }

      // The files behind this page, for anything it can't change itself.
      SettingsGroup {
        visible: page.shownConfigFiles.length > 0
        title: qsTr("Config Files")
        footer: qsTr("Opens in your default editor, chosen in General › Default Apps.")
        Repeater {
          model: page.shownConfigFiles
          delegate: ButtonRow {
            required property var modelData
            glyph: "\u{F0DC9}"
            label: modelData.name
            sublabel: modelData.path
            text: qsTr("Open…")
            onClicked: backend.act("edit", [modelData.key])
          }
        }
      }

      // Restore Defaults, below everything a pane shows.
      SettingsGroup {
        visible: page.resetPane.length > 0
        ButtonRow {
          label: qsTr("Restore Hexciri's defaults")
          sublabel: qsTr("Puts this page's settings back the way Hexciri ships them")
          glyph: "\u{F099B}"
          text: qsTr("Restore Defaults…")
          onClicked: { backend.load("defaults:" + page.resetPane); restoreDialog.open() }
        }
      }
    }

    OmaDialog {
        id: restoreDialog
        objectName: "restoreDialog"
        readonly property var changes: backend.lists["defaults:" + page.resetPane] || []
        readonly property bool loading: backend.busy.indexOf("list:defaults:" + page.resetPane) >= 0
        title: qsTr("Restore Hexciri's defaults?")
        acceptText: qsTr("Restore")
        canAccept: !loading && changes.length > 0
        onAccepted: backend.act("pane.reset", [page.resetPane],
                                ["defaults:" + page.resetPane, "bar", "dock", "monitors", "fonts"], page.resetPane)
        function shown(v) {
            if (v === true) return qsTr("On")
            if (v === false) return qsTr("Off")
            return String(v).split("\n").join(" ")
        }
        Text {
            Layout.fillWidth: true
            text: restoreDialog.loading ? qsTr("Checking…")
                  : restoreDialog.changes.length === 0 ? qsTr("Everything here is already as Hexciri ships it.")
                  : qsTr("These change back:")
            horizontalAlignment: Text.AlignLeft
            color: ui.muted
            font.family: ui.font
            font.pixelSize: ui.small
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        Repeater {
            model: restoreDialog.loading ? [] : restoreDialog.changes
            delegate: Text {
                required property var modelData
                Layout.fillWidth: true
                text: qsTranslate("Setting", modelData.label) + ": "
                      + (String(modelData.value).length > 0 ? restoreDialog.shown(modelData.value) + " → " : "")
                      + restoreDialog.shown(modelData["default"])
                horizontalAlignment: Text.AlignLeft
                color: ui.fg
                font.family: ui.font
                font.pixelSize: ui.small
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }
    }
}
