import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Switches scenes automatically (see `taurus scene`). It only watches the focused window and
// the clock and asks scene.py what to do; all the decisions and every write live there.
// scene.py does nothing unless `scenes.auto` is on and never overrides a scene chosen by hand.
Item {
    id: root

    property string lastApp: ""

    // The shell's own windows (launcher, panels) must not end a game scene.
    function isShellWindow(cls) {
        let c = String(cls || "").toLowerCase();
        return c === "quickshell" || c === "unknown" || c.indexOf("qs-master") !== -1;
    }

    function tick() {
        if (tickProcess.running) {
            retry.restart();
            return;
        }
        tickProcess.command = ["python3", "-I", Caching.taurusDir + "/scripts/scene.py", "tick",
                               root.isDesktop ? "desktop" : root.lastApp];
        tickProcess.running = true;
    }

    property bool isDesktop: false

    Process {
        id: tickProcess
        running: false
        command: []
    }

    // focus changes settle for a moment before a scene may switch
    Timer {
        id: debounce
        interval: 1500
        repeat: false
        onTriggered: root.tick()
    }

    Timer {
        id: retry
        interval: 2000
        repeat: false
        onTriggered: root.tick()
    }

    // time-based scenes, and the first evaluation after the shell starts
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    Connections {
        target: CurrentFocus
        function onAppClassChanged() {
            if (root.isShellWindow(CurrentFocus.appClass)) return;
            root.isDesktop = CurrentFocus.isDesktop;
            root.lastApp = CurrentFocus.appClass;
            debounce.restart();
        }
    }
}
