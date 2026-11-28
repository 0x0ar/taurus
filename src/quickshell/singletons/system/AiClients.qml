pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// AI coding clients (Claude Code, Codex, OpenCode, Gemini CLI): which are installed, installing the
// missing ones and linking the Taurus skills. The work is done by scripts/ai-clients.sh.
Item {
    id: root

    property var clients: []
    property bool loaded: false
    property string currentId: ""
    property string lastError: ""
    property var queue: []
    readonly property bool busy: installProcess.running || skillsProcess.running
    readonly property bool listing: listProcess.running
    property string lastResult: ""
    readonly property bool skillsLinked: clients.length > 0 && clients.filter(c => c.installed).every(c => c.skills)

    readonly property string scriptPath: ((typeof Caching !== "undefined" && Caching.taurusDir) ? Caching.taurusDir : (Quickshell.env("HOME") + "/.local/share/taurus/src")) + "/scripts/ai-clients.sh"

    function refresh() {
        if (!listProcess.running) listProcess.running = true;
    }

    // Installs the missing clients among `ids`, then links the skills once for all of them.
    function setup(ids) {
        if (busy || ids.length === 0) return;
        lastError = "";
        lastResult = "";
        queue = ids.slice();
        _next();
    }

    function _next() {
        if (queue.length === 0) {
            currentId = "skills";
            skillsProcess.running = true;
            return;
        }
        let id = queue[0];
        queue = queue.slice(1);
        let c = clients.find(x => x.id === id);
        if (c && c.installed) {
            _next();
            return;
        }
        currentId = id;
        installProcess.command = ["bash", scriptPath, "install", id];
        installProcess.running = true;
    }

    function _failed(text) {
        lastError = text.trim().split("\n").slice(-1)[0] || "error";
        queue = [];
        currentId = "";
        refresh();
    }

    Process {
        id: listProcess
        command: ["bash", root.scriptPath, "status"]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: {
                try {
                    root.clients = JSON.parse(listOut.text);
                    root.loaded = true;
                } catch (e) {
                    root.lastError = String(e);
                }
            }
        }
    }

    Process {
        id: installProcess
        stderr: StdioCollector { id: installErr }
        onExited: (code) => {
            if (code !== 0) root._failed(installErr.text);
            else root._next();
        }
    }

    Process {
        id: skillsProcess
        command: ["bash", root.scriptPath, "skills"]
        stderr: StdioCollector { id: skillsErr }
        onExited: (code) => {
            if (code !== 0) {
                root._failed(skillsErr.text);
                return;
            }
            root.currentId = "";
            root.lastResult = I18n.t("guide.ai.done", "Done. Taurus skills are installed. Restart your client to load them.");
            root.refresh();
        }
    }
}
