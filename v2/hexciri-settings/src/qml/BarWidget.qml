import QtQuick
import QtQuick.Layouts

// One bar widget's options, as its manifest describes them (every field the
// shell's own widget settings know: switches, numbers, choices, text), or a
// form of Settings' own for Hexciri's widgets that draw theirs by hand.
// Changes go through `hexciri bar set`, to the instance this page was opened
// for when the bar has the widget more than once.
SettingsPage {
    id: page
    pane: "bar"
    configFiles: ["shell"]
    lists: ["bar", "weather"]

    readonly property var params: win.subParams || ({})
    readonly property string widgetId: params.id || ""
    // The widget as the bar has it now: where the page was opened from, or
    // wherever it went since.
    readonly property var widget: {
        const sections = (backend.lists.bar || {}).sections || {}
        const here = (sections[params.section] || [])[params.index]
        if (here && here.id === widgetId) return Object.assign({ section: params.section }, here)
        for (const s in sections)
            for (const w of sections[s])
                if (w.id === widgetId) return Object.assign({ section: s }, w)
        return null
    }
    readonly property var options: widget ? widget.options || {} : {}
    readonly property bool working: backend.busy.indexOf("bar.setOption") >= 0

    // Hexciri's widgets with no schema in their manifest.
    readonly property var forms: ({
        "hexciri.clock": [
            { key: "format", type: "clock", label: qsTr("Clock"), choicesFrom: "general.clockFormat", defaultValue: "dddd HH:mm" },
            { key: "formatAlt", type: "clock", label: qsTr("After a click"), choicesFrom: "general.clockFormat",
              defaultValue: "d MMMM 'W'ww yyyy" },
            { key: "verticalFormat", type: "clock", label: qsTr("On a bar at the side"),
              choicesFrom: "general.clockVerticalFormat", defaultValue: "HH\n—\nmm" }
        ],
        "hexciri.weather": [
            { key: "unit", type: "enum", label: qsTr("Units"), defaultValue: "",
              options: [{ value: "", label: qsTr("As your language uses") }, { value: "metric", label: qsTr("Metric (°C)") },
                        { value: "imperial", label: qsTr("Imperial (°F)") }] },
            { key: "refreshMinutes", type: "integer", label: qsTr("Check for new weather every"), min: 5, max: 120, step: 5,
              defaultValue: 15, unit: "minutes" }
        ],
        "hexciri.spacer": [
            { key: "size", type: "integer", label: qsTr("Size"), min: 2, max: 200, step: 2, defaultValue: 8, unit: "px" }
        ],
        "hexciri.active-window": [
            { key: "maxWidth", type: "integer", label: qsTr("Longest title"), min: 100, max: 800, step: 10,
              defaultValue: 280, unit: "px" }
        ]
    })
    readonly property var fields: widget && (widget.schema || []).length > 0 ? widget.schema : (forms[widgetId] || [])

    function valueOf(field) {
        const v = options[field.key]
        return v !== undefined && v !== null ? v : field.defaultValue
    }
    function set(field, value) {
        if (!widget) return
        backend.act("bar.setOption", [widgetId, field.key, JSON.stringify(value === undefined ? null : value),
                                      widget.section, widget.index], ["bar"])
    }
    function choicesOf(field) {
        if (field.type === "clock") {
            const now = page.now
            return (backend.meta(field.choicesFrom).choices || []).map(f => ({
                value: f, text: Qt.locale().toString(now, f).split("\n").join(" / ") }))
        }
        return (field.options || []).map(o => typeof o === "object"
            ? { value: o.value, text: o.label || String(o.value) } : { value: o, text: String(o) })
    }
    function unitText(field, v) {
        const n = Number(v).toLocaleString(Qt.locale(), 'f', field.type === "number" ? 1 : 0)
        if (field.unit === "px") return qsTr("%1 px").arg(n)
        if (field.unit === "minutes") return qsTr("%n minutes", "", Math.round(v))
        return n
    }
    property date now: new Date()

    SettingsGroup {
        separated: false
        visible: !page.widget
        SettingRow {
            label: backend.lists.bar ? qsTr("This widget isn't on the bar any more.") : ""
        }
    }

    SettingsGroup {
        visible: !!page.widget
        title: page.widget ? page.widget.name : ""
        footer: page.fields.length === 0 ? qsTr("This widget has nothing to set.")
              : page.widget && page.widget.description ? page.widget.description : ""

        Repeater {
            model: page.fields.filter(f => f.type !== "multiselect")
            delegate: SettingRow {
                id: frow
                required property var modelData
                readonly property var field: modelData
                readonly property var value: page.valueOf(field)
                readonly property bool bounded: (field.type === "integer" || field.type === "number")
                                                && field.min !== undefined && field.max !== undefined
                readonly property bool choice: field.type === "enum" || field.type === "clock"
                label: field.label || field.key
                sublabel: field.description || ""
                busy: page.working

                OmaToggle {
                    visible: frow.field.type === "boolean"
                    checked: !!frow.value
                    interactive: !page.working
                    onToggled: page.set(frow.field, !frow.value)
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: frow.label
                    Accessible.checked: checked
                }
                ChoiceBox {
                    id: choiceBox
                    visible: frow.choice
                    enabled: !page.working
                    maxWidth: ui.s(260)
                    readonly property var choices: {
                        const list = frow.choice ? page.choicesOf(frow.field) : []
                        if (frow.value !== undefined && !list.some(o => o.value === frow.value))
                            list.push({ value: frow.value, text: String(frow.value).split("\n").join(" / ") })
                        return list
                    }
                    model: choices
                    textRole: "text"
                    valueRole: "value"
                    currentIndex: choices.findIndex(o => o.value === frow.value)
                    onActivated: {
                        page.set(frow.field, currentValue)
                        currentIndex = Qt.binding(() => choices.findIndex(o => o.value === frow.value))
                    }
                    Accessible.name: frow.label
                }
                Row {
                    visible: frow.bounded
                    spacing: ui.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    OmaSlider {
                        id: slider
                        width: ui.s(180)
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: !page.working
                        from: frow.field.min || 0
                        to: frow.field.max || 100
                        stepSize: frow.field.step || (frow.field.type === "integer" ? 1 : 0.1)
                        snapMode: OmaSlider.SnapAlways
                        value: Number(frow.value) || from
                        onPressedChanged: if (!pressed) {
                            page.set(frow.field, frow.field.type === "integer" ? Math.round(value) : value)
                            value = Qt.binding(() => Number(frow.value) || from)
                        }
                        Accessible.name: frow.label
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: ui.s(84)
                        text: page.unitText(frow.field, slider.value)
                        color: ui.fg
                        font.family: ui.font
                        font.pixelSize: ui.small
                        horizontalAlignment: Text.AlignRight
                        textFormat: Text.PlainText
                    }
                }
                OmaField {
                    id: textField
                    visible: frow.field.type === "string" || frow.field.type === "path"
                             || ((frow.field.type === "integer" || frow.field.type === "number") && !frow.bounded)
                    width: Math.max(ui.s(110), Math.min(ui.s(240), frow.controlRoom))
                    text: frow.value === undefined || frow.value === null ? "" : String(frow.value)
                    placeholderText: frow.field.placeholderText || ""
                    inputMethodHints: frow.field.type === "integer" || frow.field.type === "number" ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
                    onEditingFinished: {
                        let v = text
                        if (frow.field.type === "integer") v = parseInt(text, 10)
                        else if (frow.field.type === "number") v = parseFloat(text)
                        if ((frow.field.type === "integer" || frow.field.type === "number") && isNaN(v)) return
                        if (v !== frow.value) page.set(frow.field, v)
                    }
                    Accessible.name: frow.label
                }
            }
        }
    }

    // A list of switches for each field that picks several things; none
    // picked means all of them.
    Repeater {
        model: page.widget ? page.fields.filter(f => f.type === "multiselect") : []
        delegate: SettingsGroup {
            id: multi
            required property var modelData
            readonly property var picked: page.valueOf(modelData) || []
            title: modelData.label || modelData.key
            footer: picked.length === 0 ? (modelData.noSelectionText || qsTr("None picked: all of them show."))
                                        : (modelData.description || "")
            Repeater {
                model: multi.modelData.options || []
                delegate: SettingRow {
                    id: orow
                    required property var modelData
                    readonly property var option: typeof modelData === "object" ? modelData : { value: modelData, label: String(modelData) }
                    readonly property bool on: multi.picked.indexOf(option.value) >= 0
                    label: option.label || String(option.value)
                    sublabel: option.description || ""
                    clickable: !page.working
                    onActivated: toggle.toggled()
                    OmaToggle {
                        id: toggle
                        checked: orow.on
                        interactive: !page.working
                        onToggled: page.set(multi.modelData, orow.on ? multi.picked.filter(v => v !== orow.option.value)
                                                                    : multi.picked.concat([orow.option.value]))
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: orow.label
                        Accessible.checked: checked
                    }
                }
            }
        }
    }

    // Where the weather is for, which the weather widget keeps apart from
    // its options.
    SettingsGroup {
        visible: page.widgetId === "hexciri.weather"
        title: qsTr("Location")
        footer: qsTr("Leave it to find your city from your internet connection, or type one.")
        SettingRow {
            id: placeRow
            label: qsTr("Weather for")
            readonly property var weather: backend.lists.weather || ({})
            sublabel: weather.set ? weather.name : qsTr("Found from your internet connection")
            busy: backend.busy.indexOf("weather.location") >= 0
            OmaField {
                id: place
                width: Math.max(ui.s(110), Math.min(ui.s(200), placeRow.controlRoom - setPlace.width - ui.s(8)))
                placeholderText: qsTr("City")
                onAccepted: setPlace.clicked()
            }
            OmaButton {
                id: setPlace
                text: qsTr("Set")
                enabled: place.text.trim().length > 0
                anchors.verticalCenter: parent.verticalCenter
                onClicked: { backend.act("weather.location", [place.text.trim()], ["weather"]); place.text = "" }
            }
        }
        ButtonRow {
            visible: !!(backend.lists.weather || {}).set
            label: qsTr("Find it from your internet connection")
            text: qsTr("Use Automatic")
            onClicked: backend.act("weather.location", [""], ["weather"])
        }
    }

    SettingsGroup {
        visible: !!page.widget && Object.keys(page.options).length > 0 && page.fields.length > 0
        ButtonRow {
            label: qsTr("Restore this widget's defaults")
            glyph: "\u{F099B}"
            text: qsTr("Restore")
            enabled: !page.working
            onClicked: {
                for (const f of page.fields)
                    if (page.options[f.key] !== undefined) page.set(f, f.defaultValue !== undefined ? f.defaultValue : null)
            }
        }
    }
}
