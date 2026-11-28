import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/buttons"
import "../../reusables/inputs"
import "../../reusables/guide"

// Resolution, refresh rate, rotation and VRR of one output (niri), with a confirm-or-revert bar.
ColumnLayout {
    id: rowsRoot
    required property var rootObj
    required property string monName

    readonly property var out: DisplayOutputs.find(monName)
    readonly property bool waiting: DisplayOutputs.pending !== null && DisplayOutputs.pending.name === monName
    readonly property var cur: out && out.current ? out.current : null
    readonly property var resolutions: out ? out.resolutions : []
    readonly property int resIndex: {
        if (!cur) return -1;
        return resolutions.findIndex(r => r.width === cur.width && r.height === cur.height);
    }
    readonly property var rates: resIndex >= 0 ? resolutions[resIndex].rates : []
    readonly property var vrrModes: ["off", "always", "games"]
    readonly property var transforms: ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]

    visible: DisplayOutputs.supported && out !== null
    Layout.fillWidth: true
    spacing: rootObj.s(8)

    Component.onCompleted: DisplayOutputs.refresh()

    function transformLabel(t) {
        switch (t) {
        case "normal": return I18n.t("guide.display.output.transform.normal", "Normal");
        case "90": return "90°";
        case "180": return "180°";
        case "270": return "270°";
        case "flipped": return I18n.t("guide.display.output.transform.flipped", "Flipped");
        default: return I18n.t("guide.display.output.transform.flipped", "Flipped") + " " + t.replace("flipped-", "") + "°";
        }
    }

    function vrrLabel(m) {
        if (m === "always") return I18n.t("guide.display.output.vrr.always", "Always on");
        if (m === "games") return I18n.t("guide.display.output.vrr.games", "Only in games");
        return I18n.t("guide.display.output.vrr.off", "Off");
    }

    function pickResolution(i) {
        let r = resolutions[i];
        if (!r || !cur) return;
        // keep the refresh rate when the new resolution has it, otherwise take the highest one
        let hz = r.rates.indexOf(cur.refresh) >= 0 ? cur.refresh : r.rates[0];
        DisplayOutputs.change(monName, { "mode": r.width + "x" + r.height + "@" + (hz / 1000).toFixed(3) });
    }

    function pickRate(i) {
        if (!cur || rates[i] === undefined) return;
        DisplayOutputs.change(monName, { "mode": cur.width + "x" + cur.height + "@" + (rates[i] / 1000).toFixed(3) });
    }

    component OutputDropdown: Dropdown {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        implicitWidth: rootObj.s(180)
        implicitHeight: rootObj.s(32)
        enabled: !DisplayOutputs.pending || rowsRoot.waiting
        accentColor: ThemeBackend.mauve
        baseColor: ThemeBackend.surface0
        hoverColor: ThemeBackend.surface1
        dropdownColor: ThemeBackend.surface0
        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
        textColor: ThemeBackend.text
        activeTextColor: ThemeBackend.crust
        fontPixelSize: rootObj.s(11)
        fuzzySearch: false
    }

    SettingsRow {
        rootObj: rowsRoot.rootObj
        settingId: "display_resolution_" + rowsRoot.monName
        section: rowsRoot.monName
        searchKeywords: "display resolution size 4k 1440p 1080p screen mode monitor " + rowsRoot.monName
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰍹"
        title: I18n.t("guide.display.output.resolution.title", "Resolution")
        description: I18n.t("guide.display.output.resolution.desc", "Size of the picture the screen shows")

        OutputDropdown {
            options: rowsRoot.resolutions.map(r => r.width + " × " + r.height)
            currentIndex: rowsRoot.resIndex
            onValueChanged: function(index, value) {
                if (index !== rowsRoot.resIndex) rowsRoot.pickResolution(index);
            }
        }
    }

    SettingsRow {
        rootObj: rowsRoot.rootObj
        settingId: "display_refresh_" + rowsRoot.monName
        section: rowsRoot.monName
        searchKeywords: "display refresh rate hz hertz fps 60 120 144 monitor " + rowsRoot.monName
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰓅"
        title: I18n.t("guide.display.output.refresh.title", "Refresh rate")
        description: I18n.t("guide.display.output.refresh.desc", "How many times per second the screen updates")

        OutputDropdown {
            options: rowsRoot.rates.map(r => DisplayOutputs.formatRate(r) + " Hz")
            currentIndex: rowsRoot.cur ? rowsRoot.rates.indexOf(rowsRoot.cur.refresh) : -1
            onValueChanged: function(index, value) {
                if (rowsRoot.cur && rowsRoot.rates[index] !== rowsRoot.cur.refresh) rowsRoot.pickRate(index);
            }
        }
    }

    SettingsRow {
        visible: rowsRoot.out !== null && rowsRoot.out.vrr_supported
        rootObj: rowsRoot.rootObj
        settingId: "display_vrr_" + rowsRoot.monName
        section: rowsRoot.monName
        searchKeywords: "display vrr variable refresh rate adaptive sync freesync g-sync tearing gaming " + rowsRoot.monName
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰢮"
        title: I18n.t("guide.display.output.vrr.title", "Variable refresh rate (VRR)")
        description: I18n.t("guide.display.output.vrr.desc", "Adaptive Sync / FreeSync / G-Sync. \"Only in games\" turns it on for game windows (Steam, gamescope) only")

        OutputDropdown {
            options: rowsRoot.vrrModes.map(m => rowsRoot.vrrLabel(m))
            currentIndex: rowsRoot.out ? rowsRoot.vrrModes.indexOf(rowsRoot.out.vrr_mode) : -1
            onValueChanged: function(index, value) {
                if (rowsRoot.out && rowsRoot.vrrModes[index] !== rowsRoot.out.vrr_mode)
                    DisplayOutputs.change(rowsRoot.monName, { "vrr": rowsRoot.vrrModes[index] });
            }
        }
    }

    SettingsRow {
        rootObj: rowsRoot.rootObj
        settingId: "display_rotation_" + rowsRoot.monName
        section: rowsRoot.monName
        searchKeywords: "display rotation rotate orientation transform flip portrait landscape monitor " + rowsRoot.monName
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰑵"
        title: I18n.t("guide.display.output.rotation.title", "Rotation")
        description: I18n.t("guide.display.output.rotation.desc", "Orientation of the screen")

        OutputDropdown {
            options: rowsRoot.transforms.map(t => rowsRoot.transformLabel(t))
            currentIndex: rowsRoot.out ? rowsRoot.transforms.indexOf(rowsRoot.out.transform) : -1
            onValueChanged: function(index, value) {
                if (rowsRoot.out && rowsRoot.transforms[index] !== rowsRoot.out.transform)
                    DisplayOutputs.change(rowsRoot.monName, { "transform": rowsRoot.transforms[index] });
            }
        }
    }

    Rectangle {
        visible: rowsRoot.waiting
        Layout.fillWidth: true
        implicitHeight: confirmRow.implicitHeight + rootObj.s(20)
        radius: ThemeBackend.borderRadius
        color: Qt.alpha(ThemeBackend.yellow, 0.14)
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.yellow, 0.5)

        RowLayout {
            id: confirmRow
            anchors.fill: parent
            anchors.margins: rootObj.s(10)
            spacing: rootObj.s(10)

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: I18n.t("guide.display.output.confirm", "Keep these display settings? Reverting in {seconds}s")
                    .replace("{seconds}", DisplayOutputs.pending ? DisplayOutputs.pending.seconds : 0)
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(12)
                color: ThemeBackend.text
            }

            ClickButton {
                maxWidth: rootObj.s(120)
                implicitHeight: rootObj.s(32)
                cornerRadius: ThemeBackend.borderRadius
                buttonText: I18n.t("guide.display.output.revert", "Revert")
                textFontSize: rootObj.s(12)
                accentColor: ThemeBackend.surface1
                textColor: ThemeBackend.text
                onClicked: DisplayOutputs.revert()
            }

            ClickButton {
                maxWidth: rootObj.s(120)
                implicitHeight: rootObj.s(32)
                cornerRadius: ThemeBackend.borderRadius
                buttonText: I18n.t("guide.display.output.keep", "Keep")
                textFontSize: rootObj.s(12)
                accentColor: ThemeBackend.mauve
                textColor: ThemeBackend.crust
                onClicked: DisplayOutputs.keep()
            }
        }
    }

    Text {
        visible: DisplayOutputs.error !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: DisplayOutputs.error
        font.family: ThemeBackend.fontFamily
        font.pixelSize: rootObj.s(11)
        color: ThemeBackend.red
    }
}
