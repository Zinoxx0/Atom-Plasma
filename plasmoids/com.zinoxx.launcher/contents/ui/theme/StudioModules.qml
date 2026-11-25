import QtQuick
import Atom
import Rice

// The Theme page's Misc Modules: optional desktop widgets & integrations discovered from
// <repo>/modules/<id>/module.json and ~/.config/atom-plasma/modules/<id>/module.json.
// Every module renders its master toggle plus its declared config schema automatically
// (bool toggles, choice chip rows with optional colour dots) so users can drop in their own
// standalone modules (ChatGPT, Grok, Codex, ...) without editing Atom Plasma core.
Column {
    id: mm
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property var mods: studio.model.modules || []
    readonly property var missingBar: studio.model.missingBarModules || []
    width: studio.mainWidth
    spacing: d(22)

    Text {
        visible: !mm.mods.length
        text: "No modules found yet."
        color: mm.lk.fgDim
        font.family: Tokens.font.ui; font.pixelSize: mm.d(17)
    }

    Repeater {
        model: mm.mods
        Rectangle {
            id: card
            required property var modelData
            readonly property var mod: modelData
            readonly property var mDraft: { mm.studio.model.draft; return mm.studio.model.modDraft(mod.id) }
            readonly property bool modOn: mDraft.enabled !== undefined ? !!mDraft.enabled : !!mod.enabled
            readonly property var cfg: Object.assign({}, mod.config || {}, mDraft.config || {})
            readonly property color accentCol: mod.accent ? mod.accent : mm.lk.primary
            width: mm.width
            implicitHeight: cardCol.implicitHeight + mm.d(40)
            radius: mm.d(22)
            color: C.alpha(mm.lk.surfaceLowest, modOn ? 0.62 : 0.42)
            border.width: mm.d(1.5)
            border.color: modOn ? C.alpha(accentCol, 0.42) : C.alpha(mm.lk.fg, 0.12)
            opacity: modOn ? 1.0 : 0.72
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(220) } }
            Behavior on border.color { ColorAnimation { duration: Tokens.ms(220) } }

            Column {
                id: cardCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: mm.d(22) }
                spacing: mm.d(18)

                // Header: icon badge + name/subtitle + master On/Off toggle
                Item {
                    width: parent.width
                    height: Math.max(mm.d(56), titleCol.implicitHeight)
                    Row {
                        anchors.left: parent.left
                        anchors.right: modSwitch.left
                        anchors.rightMargin: mm.d(18)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: mm.d(16)

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: mm.d(46); height: width; radius: mm.d(14)
                            color: C.alpha(card.accentCol, 0.18)
                            border.width: mm.d(1)
                            border.color: C.alpha(card.accentCol, 0.35)
                            Text {
                                anchors.centerIn: parent
                                text: card.mod.icon || "extension"
                                color: card.accentCol
                                font.family: Tokens.font.icons
                                font.pixelSize: mm.d(24)
                            }
                        }

                        Column {
                            id: titleCol
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - mm.d(62))
                            spacing: mm.d(4)
                            Row {
                                spacing: mm.d(10)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card.mod.name
                                    color: mm.lk.fg
                                    font.family: mm.studio.wideFamily
                                    font.variableAxes: mm.studio.wideAxes(110, 600)
                                    font.pixelSize: mm.d(22)
                                }
                                Rectangle {
                                    visible: !card.mod.builtin || !card.mod.detected
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: badgeT.implicitWidth + mm.d(16); height: mm.d(22); radius: height / 2
                                    color: !card.mod.builtin ? C.alpha(mm.lk.primary, 0.18) : C.alpha(mm.lk.fg, 0.10)
                                    Text {
                                        id: badgeT
                                        anchors.centerIn: parent
                                        text: !card.mod.builtin ? "Custom" : "Not detected"
                                        color: !card.mod.builtin ? mm.lk.primary : mm.lk.fgDim
                                        font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mm.d(11.5)
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: card.mod.subtitle || ""
                                color: mm.lk.fgDim
                                font.family: Tokens.font.ui; font.pixelSize: mm.d(14.5)
                            }
                        }
                    }

                    StudioToggle {
                        id: modSwitch
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        studio: mm.studio
                        fkey: "mod:on:" + card.mod.id
                        text: card.modOn ? "On" : "Off"
                        chosen: card.modOn
                        desc: "<b>" + card.mod.name + "</b> " + (card.mod.subtitle || "Toggle this module on or off.")
                        onActivated: { mm.studio.model.setModuleEnabled(card.mod.id, !card.modOn); mm.studio.relensSoon() }
                    }
                }

                // Dynamic options rendered from module.json `config` schema
                Column {
                    visible: card.modOn && (card.mod.schema || []).length > 0
                    width: parent.width
                    spacing: mm.d(14)

                    Rectangle { width: parent.width; height: 1; color: C.alpha(mm.lk.fg, 0.10) }

                    // Choice options (each its own labelled chip group, e.g. Gemini star colours)
                    Repeater {
                        model: (card.mod.schema || []).filter(o => o.type === "choice")
                        Column {
                            id: choiceRow
                            required property var modelData
                            readonly property var opt: modelData
                            readonly property string curVal: String(card.cfg[opt.key] ?? opt.default ?? "")
                            width: parent.width
                            spacing: mm.d(8)

                            StudioCap { studio: mm.studio; text: choiceRow.opt.label }
                            Flow {
                                width: parent.width
                                spacing: mm.d(10)
                                Repeater {
                                    model: choiceRow.opt.options || []
                                    StudioChip {
                                        required property var modelData
                                        studio: mm.studio
                                        fkey: "mod:" + card.mod.id + ":" + choiceRow.opt.key + ":" + modelData.value
                                        text: modelData.label
                                        dots: modelData.dots || []
                                        chosen: choiceRow.curVal === String(modelData.value)
                                        desc: "<b>" + modelData.label + "</b> " + (choiceRow.opt.desc || "")
                                        act: "Use"
                                        onActivated: mm.studio.model.setModuleOption(card.mod.id, choiceRow.opt.key, modelData.value)
                                    }
                                }
                            }
                        }
                    }

                    // Boolean options (clean toggle chip strip)
                    Flow {
                        visible: (card.mod.schema || []).some(o => o.type === "bool")
                        width: parent.width
                        spacing: mm.d(10)
                        Repeater {
                            model: (card.mod.schema || []).filter(o => o.type === "bool")
                            StudioChip {
                                required property var modelData
                                readonly property bool val: card.cfg[modelData.key] !== undefined ? !!card.cfg[modelData.key] : !!modelData.default
                                studio: mm.studio
                                fkey: "mod:" + card.mod.id + ":" + modelData.key
                                icon: val ? "check" : ""
                                text: modelData.label
                                chosen: val
                                desc: "<b>" + modelData.label + "</b> " + (modelData.desc || "")
                                act: val ? "Turn off" : "Turn on"
                                onActivated: mm.studio.model.setModuleOption(card.mod.id, modelData.key, !val)
                            }
                        }
                    }
                }
            }
        }
    }

    // Notice when an enabled module isn't mounted on the panel yet
    Rectangle {
        visible: mm.missingBar.length > 0
        width: mm.width
        implicitHeight: noteRow.implicitHeight + mm.d(28)
        radius: mm.d(16)
        color: C.alpha(mm.lk.primary, 0.14)
        border.width: mm.d(1)
        border.color: C.alpha(mm.lk.primary, 0.35)
        Row {
            id: noteRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: mm.d(18) }
            spacing: mm.d(12)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "info"; color: mm.lk.primary; font.family: Tokens.font.icons; font.pixelSize: mm.d(20) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - mm.d(36)
                wrapMode: Text.Wrap
                text: "New bar widget(s) ready (" + mm.missingBar.join(", ") + "). Run <b>python3 panel/build.py</b> once to place them in the taskbar's meters island — toggling after that is instant."
                textFormat: Text.StyledText
                color: mm.lk.fg
                font.family: Tokens.font.ui; font.pixelSize: mm.d(13.5)
            }
        }
    }

    // Custom drop-in hint for ChatGPT / Grok / community modules
    Rectangle {
        width: mm.width
        implicitHeight: customRow.implicitHeight + mm.d(30)
        radius: mm.d(18)
        color: C.alpha(mm.lk.surfaceLowest, 0.36)
        border.width: mm.d(1.5)
        border.color: C.alpha(mm.lk.fg, 0.14)
        Row {
            id: customRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: mm.d(20) }
            spacing: mm.d(14)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "add_circle"
                color: mm.lk.fgDim
                font.family: Tokens.font.icons; font.pixelSize: mm.d(22)
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - mm.d(40)
                spacing: mm.d(3)
                Text {
                    text: "Build your own standalone modules (ChatGPT, Grok, Codex…)"
                    color: mm.lk.fg
                    font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mm.d(14.5)
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Drop a folder with module.json (+ optional plasmoid/ and systemd/) into " + (mm.studio.model.modulesDir || "~/.config/atom-plasma/modules") + " and run rice.py install."
                    color: mm.lk.fgDim
                    font.family: Tokens.font.ui; font.pixelSize: mm.d(13)
                }
            }
        }
    }
}
