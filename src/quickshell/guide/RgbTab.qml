import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/buttons"
import "../reusables/guide"

GuideTab {
    id: rgbTabRoot

    property var devices: []
    property string statusText: ""
    property bool busy: false
    property int listRetries: 0

    Timer {
        id: retryTimer
        interval: 8000
        repeat: false
        onTriggered: listProcess.running = true
    }

    onVisibleChanged: if (visible) listProcess.running = true

    function refresh() {
        listProcess.running = false;
        listProcess.running = true;
    }

    function turnOffAll() {
        if (rgbTabRoot.busy) return;
        rgbTabRoot.busy = true;
        rgbTabRoot.statusText = I18n.t("guide.rgb.working", "Apagando RGB...");
        offProcess.running = false;
        offProcess.running = true;
    }

    Process {
        id: listProcess
        running: true
        command: ["/usr/bin/openrgb", "--list-devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                var found = [];
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var match = /^\s*(\d+):\s*(.+?)\s*$/.exec(lines[i]);
                    if (match) found.push({ id: match[1], name: match[2] });
                }
                rgbTabRoot.devices = found;
                if (found.length > 0) rgbTabRoot.listRetries = 0;
                rgbTabRoot.statusText = found.length > 0
                    ? I18n.t("guide.rgb.found", "Componentes detectados: ") + found.length
                    : I18n.t("guide.rgb.loading", "Buscando dispositivos RGB...");
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0)
                    rgbTabRoot.statusText = this.text.trim();
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0 || rgbTabRoot.devices.length > 0) return;
            if (rgbTabRoot.listRetries < 2) {
                rgbTabRoot.listRetries++;
                rgbTabRoot.statusText = I18n.t("guide.rgb.loading", "Buscando dispositivos RGB...");
                retryTimer.start();
            } else {
                rgbTabRoot.statusText = I18n.t("guide.rgb.none", "No se detectaron dispositivos RGB");
            }
        }
    }

    Process {
        id: offProcess
        running: false
        command: ["/usr/bin/openrgb", "--profile", "RGB_Off"]
        onExited: function(exitCode) {
            rgbTabRoot.busy = false;
            if (exitCode === 0) {
                rgbTabRoot.statusText = I18n.t("guide.rgb.done", "RGB apagado en todos los componentes");
                rgbTabRoot.refresh();
            } else {
                rgbTabRoot.statusText = I18n.t("guide.rgb.failed", "No se pudo apagar el RGB (salida ") + exitCode + ")";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0)
                    rgbTabRoot.statusText = this.text.trim();
            }
        }
    }

    GuideScrollView {
        rootObj: rgbTabRoot.rootObj

        Rectangle {
            Layout.fillWidth: true
            clip: true
            radius: ThemeBackend.clampedBorderRadius
            color: cardGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, 0.4)
            implicitHeight: cardLayout.implicitHeight + rgbTabRoot.rootObj.s(12)

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
                    rootObj: rgbTabRoot.rootObj
                    settingId: "rgb_devices"
                    searchKeywords: "rgb luces led componentes ram placa corsair openrgb apagar"
                    icon: "󰔎"
                    title: I18n.t("guide.rgb.title", "Componentes RGB")
                    description: I18n.t("guide.rgb.desc", "Lista de dispositivos detectados por OpenRGB y apagado global.")
                    baseColor: "transparent"
                    hoverColor: "transparent"
                    borderWidth: 0

                    ClickButton {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        maxWidth: rgbTabRoot.rootObj.s(200)
                        implicitHeight: rgbTabRoot.rootObj.s(32)
                        enabled: !rgbTabRoot.busy && rgbTabRoot.devices.length > 0
                        opacity: enabled ? 1.0 : 0.5
                        cornerRadius: ThemeBackend.borderRadius
                        buttonText: rgbTabRoot.busy ? I18n.t("guide.rgb.working", "Apagando RGB...") : I18n.t("guide.rgb.turn_off", "Apagar todo")
                        buttonIcon: "󰔎"
                        iconFontSize: rgbTabRoot.rootObj.s(14)
                        textFontSize: rgbTabRoot.rootObj.s(12)
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.crust
                        onClicked: rgbTabRoot.turnOffAll()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(ThemeBackend.surface1, 0.3)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: rgbTabRoot.rootObj.s(12)
            spacing: rgbTabRoot.rootObj.s(8)

            Repeater {
                model: rgbTabRoot.devices

                delegate: Rectangle {
                    id: deviceTile
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: rgbTabRoot.rootObj.s(52)
                    radius: ThemeBackend.borderRadius
                    color: Qt.alpha(ThemeBackend.surface1, 0.3)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: rgbTabRoot.rootObj.s(12)
                        anchors.rightMargin: rgbTabRoot.rootObj.s(12)
                        spacing: rgbTabRoot.rootObj.s(10)

                        Text {
                            text: "󰄬"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rgbTabRoot.rootObj.s(18)
                            color: ThemeBackend.green
                            Layout.preferredWidth: rgbTabRoot.rootObj.s(22)
                            horizontalAlignment: Text.AlignHCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: rgbTabRoot.rootObj.s(1)

                            Text {
                                text: deviceTile.modelData.name
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rgbTabRoot.rootObj.s(13)
                                font.bold: true
                                color: ThemeBackend.text
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: I18n.t("guide.rgb.device_id", "Dispositivo ") + deviceTile.modelData.id
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rgbTabRoot.rootObj.s(11)
                                color: ThemeBackend.subtext0
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Text {
                visible: rgbTabRoot.devices.length === 0
                text: I18n.t("guide.rgb.loading", "Buscando dispositivos RGB...")
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rgbTabRoot.rootObj.s(12)
                color: ThemeBackend.subtext0
            }

            Text {
                Layout.fillWidth: true
                text: rgbTabRoot.statusText
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rgbTabRoot.rootObj.s(11)
                color: ThemeBackend.subtext0
                wrapMode: Text.Wrap
            }
        }
    }
}
