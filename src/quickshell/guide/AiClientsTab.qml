import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"
import "../reusables/buttons"
import "../reusables/inputs"
import "../reusables/guide"

GuideTab {
    id: aiTabRoot

    // ids ticked in the list; only the ones that are not installed yet are offered a checkbox
    property var selected: ({})
    readonly property var pending: AiClients.clients.filter(c => !c.installed && selected[c.id] === true)
    readonly property bool canRun: !AiClients.busy && (pending.length > 0 || (AiClients.clients.length > 0 && !AiClients.skillsLinked))

    function toggle(id, on) {
        let next = Object.assign({}, selected);
        next[id] = on;
        selected = next;
    }

    function statusText(c) {
        if (AiClients.busy && AiClients.currentId === c.id) return I18n.t("guide.ai.installing", "Installing...");
        if (c.installed) return I18n.t("guide.ai.installed", "Installed") + " · " + (c.skills ? I18n.t("guide.ai.skills_ok", "Taurus skills ready") : I18n.t("guide.ai.skills_missing", "Taurus skills missing"));
        return c.repo ? I18n.t("guide.ai.not_installed", "Not installed") : I18n.t("guide.ai.unavailable", "Not available in your repositories");
    }

    onVisibleChanged: if (visible) AiClients.refresh()
    Component.onCompleted: AiClients.refresh()

    GuideScrollView {
        rootObj: aiTabRoot.rootObj

        Rectangle {
            Layout.fillWidth: true
            clip: true
            radius: ThemeBackend.borderRadius
            color: cardGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, 0.4)
            implicitHeight: cardLayout.implicitHeight + rootObj.s(12)

            GlassFill {
                id: cardGlass
                anchors.fill: parent
                radius: parent.radius
                tintColor: Qt.alpha(ThemeBackend.surface0, 0.4)
                tintAmount: 0.25
            }

            ColumnLayout {
                id: cardLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 0

                SettingsRow {
                    rootObj: aiTabRoot.rootObj
                    settingId: "ai_clients"
                    searchKeywords: "ai clients claude codex opencode gemini skills agent install download llm"
                    icon: "󰧑"
                    title: I18n.t("guide.ai.title", "AI clients")
                    description: AiClients.lastError !== "" ? AiClients.lastError
                        : AiClients.busy ? (AiClients.currentId === "skills" ? I18n.t("guide.ai.linking", "Installing the Taurus skills...") : I18n.t("guide.ai.installing", "Installing..."))
                        : AiClients.lastResult !== "" ? AiClients.lastResult
                        : (AiClients.skillsLinked ? I18n.t("guide.ai.skills_ready", "Taurus skills are installed")
                                                  : I18n.t("guide.ai.desc", "Pick the ones to download. The Taurus skills are installed for all of them."))
                    baseColor: "transparent"
                    hoverColor: "transparent"
                    borderWidth: 0

                    ClickButton {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        maxWidth: rootObj.s(200)
                        implicitHeight: rootObj.s(32)
                        enabled: aiTabRoot.canRun
                        opacity: enabled ? 1.0 : 0.5
                        cornerRadius: ThemeBackend.borderRadius
                        buttonText: AiClients.busy ? I18n.t("guide.ai.working", "Working...") : I18n.t("guide.ai.install", "Install selected")
                        buttonIcon: "󰇚"
                        iconFontSize: rootObj.s(14)
                        textFontSize: rootObj.s(12)
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.crust
                        onClicked: AiClients.setup(aiTabRoot.pending.map(c => c.id))
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.alpha(ThemeBackend.surface1, 0.3)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: rootObj.s(12)
                    spacing: rootObj.s(8)

                    Repeater {
                        model: AiClients.clients

                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: rootObj.s(52)
                            radius: ThemeBackend.borderRadius
                            color: Qt.alpha(ThemeBackend.surface1, 0.3)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: rootObj.s(12)
                                anchors.rightMargin: rootObj.s(12)
                                spacing: rootObj.s(10)

                                Checkbox {
                                    size: rootObj.s(22)
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: !tile.modelData.installed
                                    enabled: tile.modelData.repo || tile.modelData.id === "claude"
                                    checked: aiTabRoot.selected[tile.modelData.id] === true
                                    baseColor: ThemeBackend.surface2
                                    hoverColor: ThemeBackend.overlay0
                                    onToggled: (on) => aiTabRoot.toggle(tile.modelData.id, on)
                                }

                                Text {
                                    visible: tile.modelData.installed
                                    text: "󰄬"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(18)
                                    color: ThemeBackend.green
                                    Layout.preferredWidth: rootObj.s(22)
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: rootObj.s(1)

                                    Text {
                                        text: tile.modelData.name
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(13)
                                        font.bold: true
                                        color: ThemeBackend.text
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: aiTabRoot.statusText(tile.modelData)
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(11)
                                        color: tile.modelData.installed ? (tile.modelData.skills ? ThemeBackend.green : ThemeBackend.yellow) : ThemeBackend.subtext0
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: AiClients.clients.length === 0
                        text: I18n.t("guide.ai.loading", "Loading...")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.subtext0
                    }
                }
            }
        }
    }
}
