import QtQuick

// Scripts Hexciri runs when something happens, from
// ~/.config/hexciri/hooks/<when>.d: your own, and Hexciri's examples, which
// run once turned on (a copy without .sample).
SettingsPage {
    id: page
    pane: "general"
    lists: ["hooks"]

    readonly property var whens: ({
        "post-boot": qsTr("After the computer starts"),
        "post-update": qsTr("After Hexciri updates"),
        "theme-set": qsTr("After the theme changes"),
        "font-set": qsTr("After the font changes"),
        "battery-low": qsTr("When the battery runs low"),
        "pre-refresh-pacman": qsTr("Before package sources are reset")
    })
    readonly property bool working: ["hook.add", "hook.remove", "hook.use", "hook.stopUsing"].some(a => backend.busy.indexOf(a) >= 0)

    SettingsGroup {
        separated: false
        footer: qsTr("A hook is a script that runs on its own at a moment you pick. Only add scripts you trust: they run as you.")
    }

    Repeater {
        model: backend.lists.hooks || []
        delegate: SettingsGroup {
            id: hookGroup
            required property var modelData
            // Examples whose copy is already listed show once, as the copy.
            readonly property var items: modelData.items.filter(i => !(!i.sample && modelData.items.some(o => o.sample && o.title === i.name)))
            title: page.whens[modelData.type] || modelData.type
            footer: items.length === 0 ? qsTr("Nothing runs then.") : ""

            Repeater {
                model: hookGroup.items
                delegate: SettingRow {
                    id: hrow
                    required property var modelData
                    label: modelData.title
                    sublabel: modelData.sample ? qsTr("An example from Hexciri") : ""
                    glyph: "\u{F0BA3}"
                    OmaToggle {
                        visible: hrow.modelData.sample
                        checked: hrow.modelData.enabled
                        interactive: !page.working
                        onToggled: backend.act(hrow.modelData.enabled ? "hook.stopUsing" : "hook.use",
                                               [hookGroup.modelData.type, hrow.modelData.name], ["hooks"])
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: hrow.label
                        Accessible.checked: checked
                    }
                    OmaButton {
                        text: qsTr("Open…")
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: backend.act("hook.edit", [hookGroup.modelData.type, hrow.modelData.name])
                    }
                    OmaButton {
                        visible: !hrow.modelData.sample
                        glyph: "\u{F0A7A}"
                        bordered: false
                        enabled: !page.working
                        tooltip: qsTr("Remove")
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: backend.act("hook.remove", [hookGroup.modelData.type, hrow.modelData.name], ["hooks"])
                    }
                }
            }
            ButtonRow {
                label: ""
                text: qsTr("Add a Script…")
                enabled: !page.working
                onClicked: backend.act("hook.add", [hookGroup.modelData.type], ["hooks"])
            }
        }
    }
}
