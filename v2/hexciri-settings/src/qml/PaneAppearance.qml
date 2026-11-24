import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

SettingsPage {
    id: page
    pane: "appearance"
    title: qsTr("Appearance")
    tagline: page.current
    glyph: "\u{F03D8}"
    description: qsTr("Choose a theme for the whole desktop, and how windows and text look.")
    lists: ["themes", "editors"]
    readonly property var editors: backend.lists.editors || ({})
    resetPane: "appearance"

    readonly property var themes: backend.lists.themes || []
    readonly property string current: backend.values["appearance.theme"] || ""
    readonly property bool switching: backend.busy.indexOf("appearance.theme") >= 0

    SettingsGroup {
        title: qsTr("Theme")
        footer: page.switching ? qsTr("Applying “%1” to the desktop…").arg(page.current)
                               : qsTr("A theme sets the colors, wallpaper, and fonts of everything at once.")
        // The current theme, opening the gallery of all of them on a page of
        // its own.
        SettingRow {
            id: themeRow
            label: page.current
            sublabel: qsTr("%n themes installed", "", page.themes.length)
            clickable: true
            busy: page.switching
            activeFocusOnTab: true
            onActivated: win.openSub("AppearanceThemes", qsTr("Themes"))
            Keys.onReturnPressed: activated()
            Keys.onSpacePressed: activated()
            // Room for the preview beside the label, and for the label, the
            // preview, and the button when they stack in a narrow window.
            implicitHeight: Math.max(Math.round(90 * ui.scale), naturalHeight)
            Rectangle {
                width: Math.round(120 * ui.scale)
                height: Math.round(72 * ui.scale)
                radius: theme.radius
                color: ui.bg
                border.width: 1
                border.color: ui.normalBorder
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: (page.themes.find(t => t.current) || {}).preview || ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 240
                    asynchronous: true
                }
            }
            OmaButton {
                text: qsTr("Browse Themes")
                anchors.verticalCenter: parent.verticalCenter
                onClicked: themeRow.activated()
            }
        }
    }

    SettingsGroup {
        title: qsTr("Windows")
        ChoiceRow {
            setting: "appearance.corners"
            label: qsTr("Window corners")
            options: [
                { value: "theme", text: qsTr("As the theme sets them") },
                { value: "sharp", text: qsTr("Sharp") },
                { value: "rounded", text: qsTr("Rounded") },
                { value: "custom", text: qsTr("Custom") }
            ]
        }
        SliderRow {
            visible: backend.values["appearance.corners"] === "custom"
            setting: "desktop.rounding"
            label: qsTr("Corner radius")
            to: 20
            format: v => qsTr("%1 px").arg(Math.round(v).toLocaleString(Qt.locale(), 'f', 0))
        }
        ChoiceRow {
            setting: "appearance.transparency"
            label: qsTr("Window transparency")
            options: [
                { value: "opaque", text: qsTr("Opaque") },
                { value: "transparent", text: qsTr("Transparent") },
                { value: "glassy", text: qsTr("Glassy") }
            ]
        }
        ToggleRow {
            setting: "appearance.animations"
            label: qsTr("Animations, blur, and shadows")
            sublabel: qsTr("Turn off on computers without a graphics card to keep things quick")
        }
        ToggleRow {
            setting: "desktop.shadow"
            label: qsTr("Shadows under windows")
            sublabel: backend.values["appearance.animations"] === false ? qsTr("Off while animations are off") : ""
            dimmed: backend.values["appearance.animations"] === false || value === undefined
        }
    }

    // Hexciri themes these apps too when it can; each can keep its own.
    SettingsGroup {
        visible: !!(page.editors.code || page.editors.cursor || page.editors.codium)
        title: qsTr("Other Apps")
        footer: qsTr("Turn one off to keep the theme you chose in that app.")
        ToggleRow { visible: !!page.editors.code; setting: "appearance.themeVscode"; label: qsTr("Theme VS Code") }
        ToggleRow { visible: !!page.editors.cursor; setting: "appearance.themeCursor"; label: qsTr("Theme Cursor") }
        ToggleRow { visible: !!page.editors.codium; setting: "appearance.themeCodium"; label: qsTr("Theme VSCodium") }
        // Hexciri: herdr theme sync removed, Herdr is out of v2 scope.
    }


}
