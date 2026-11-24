import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

SettingsPage {
    id: page
    pane: "general"
    lists: ["about", "system"]

    readonly property var about: backend.lists.about || ({})
    readonly property var updates: backend.lists.updates || ({})
    readonly property bool checking: backend.busy.indexOf("list:updates") >= 0

    SettingsGroup {
        footer: qsTr("Updates run in a terminal so you can follow along and answer any questions. Hexciri updates the system, its apps, and itself together.")
        InfoRow {
            label: qsTr("Hexciri")
            value: page.about.hexciri || ""
        }
        ButtonRow {
            label: page.checking ? qsTr("Checking…")
                 : !page.updates.checked ? qsTr("Check whether an update is waiting")
                 : page.updates.available ? qsTr("An update is available")
                 : qsTr("Hexciri is up to date")
            sublabel: page.updates.checked && page.updates.available ? (page.updates.text || "") : ""
            text: qsTr("Check Now")
            busy: page.checking
            onClicked: backend.load("updates")
        }
        ButtonRow {
            label: qsTr("Update the system")
            text: qsTr("Update Now")
            highlighted: page.updates.available === true
            onClicked: backend.act("launch", ["update"])
        }
    }

    SettingsGroup {
        title: qsTr("Hexciri Updates")
        footer: qsTr("Hexciri has no release channel. Updates follow the nyx branch: hexciri update pulls the latest installer and re-applies it.")
        InfoRow {
            label: qsTr("Channel")
            value: qsTr("nyx branch, no channel")
        }
    }

    SettingsGroup {
        ButtonRow {
            visible: (backend.lists.system || {}).themeExtras === true
            label: qsTr("Themes you installed")
            sublabel: qsTr("Get the latest versions from where they came from")
            text: qsTr("Update Themes")
            onClicked: backend.act("launch", ["themeUpdate"])
        }
        ButtonRow {
            label: qsTr("Clock")
            sublabel: qsTr("If the time is off, sync it with the internet again")
            text: qsTr("Fix the Time")
            onClicked: backend.act("launch", ["timeSync"])
        }
        ButtonRow {
            label: qsTr("Firmware")
            sublabel: qsTr("Updates for your computer's hardware, from fwupd")
            text: qsTr("Update Firmware")
            onClicked: backend.act("launch", ["firmware"])
        }
    }
}
