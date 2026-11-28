pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Resolution, refresh rate, VRR and rotation of the outputs (niri). A change is applied right away but
// only kept after the user confirms it; if they do not, it is reverted so a bad mode never sticks.
// The work is done by scripts/display-output.py.
Item {
    id: root

    property var outputs: []
    property bool loaded: false
    property string error: ""
    // { name, previous: {mode, vrr, transform}, seconds } while a change waits for confirmation
    property var pending: null
    readonly property int confirmSeconds: 15
    readonly property bool supported: Compositor.name === "niri"

    readonly property string scriptPath: ((typeof Caching !== "undefined" && Caching.taurusDir) ? Caching.taurusDir : (Quickshell.env("HOME") + "/.local/share/taurus/src")) + "/scripts/display-output.py"

    function find(name) {
        return outputs.find(o => o.name === name) || null;
    }

    function modeString(c) {
        return c.width + "x" + c.height + "@" + (c.refresh / 1000).toFixed(3);
    }

    function formatRate(mhz) {
        return (mhz / 1000).toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
    }

    function refresh() {
        if (supported && !listProcess.running) listProcess.running = true;
    }

    // change: any of { mode: "WxH@Hz", vrr: "off"|"always"|"games", transform: "normal"|"90"|... }
    function change(name, change) {
        let o = find(name);
        if (!o || applyProcess.running) return;
        error = "";
        if (!pending || pending.name !== name) {
            pending = {
                "name": name,
                "previous": { "mode": o.current ? modeString(o.current) : "", "vrr": o.vrr_mode, "transform": o.transform },
                "seconds": confirmSeconds
            };
        } else {
            pending = Object.assign({}, pending, { "seconds": confirmSeconds });
        }
        _run(name, change);
        countdown.restart();
    }

    function _run(name, change) {
        let cmd = ["python3", scriptPath, "apply", name];
        if (change.mode) cmd.push("--mode", change.mode);
        if (change.vrr) cmd.push("--vrr", change.vrr);
        if (change.transform) cmd.push("--transform", change.transform);
        applyProcess.command = cmd;
        applyProcess.running = true;
    }

    function keep() {
        if (!pending) return;
        countdown.stop();
        persistProcess.command = ["python3", scriptPath, "persist", pending.name];
        persistProcess.running = true;
    }

    function revert() {
        if (!pending) return;
        countdown.stop();
        let p = pending;
        pending = null;
        let change = { "transform": p.previous.transform, "vrr": p.previous.vrr };
        if (p.previous.mode !== "") change.mode = p.previous.mode;
        _run(p.name, change);
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            if (!root.pending) { stop(); return; }
            let left = root.pending.seconds - 1;
            if (left <= 0) { root.revert(); return; }
            root.pending = Object.assign({}, root.pending, { "seconds": left });
        }
    }

    Process {
        id: listProcess
        command: ["python3", root.scriptPath, "info"]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: {
                try {
                    root.outputs = JSON.parse(listOut.text);
                    root.loaded = true;
                } catch (e) {
                    root.error = String(e);
                }
            }
        }
    }

    Process {
        id: applyProcess
        stderr: StdioCollector { id: applyErr }
        onExited: (code) => {
            if (code !== 0) {
                root.error = applyErr.text.trim().split("\n").slice(-1)[0] || "error";
                if (root.pending) { countdown.stop(); root.pending = null; }
            }
            root.refresh();
        }
    }

    Process {
        id: persistProcess
        stderr: StdioCollector { id: persistErr }
        onExited: (code) => {
            if (code !== 0) root.error = persistErr.text.trim().split("\n").slice(-1)[0] || "error";
            root.pending = null;
            root.refresh();
        }
    }
}
