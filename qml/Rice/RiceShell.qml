import QtQuick

// Runs shell commands for the rice widgets, with the API of the executable DataSource it replaces, so
// a widget only swaps the declaration: connectSource(cmd) runs cmd, newData(cmd, data) answers with
// data["stdout"], data["stderr"] and data["exit code"], disconnectSource() is a no-op.
//
//   RiceShell { id: sh; onNewData: (source, data) => ... }      sh.connectSource("cmd #tag")
//   sh.exec("tag", ["python3", sh.home + "/.config/plasma-rice/rice.py", "theme", "set", ...])
//
// Why not one long-lived DataSource per widget: the executable engine is shared by all of plasmashell,
// and every DataSource bound to it "clears" each finished command from its data map, which ADDS that
// name to the map and rebuilds the map's metaobject (Plasma5Support::DataSource::removeSource ->
// QQmlPropertyMap::clear). So a long-lived DataSource gains one property for every command any widget
// runs, each command costs (DataSources x commands so far), and after two hours a wallpaper change
// froze plasmashell for ~10 s (2026-10-16). Here each command gets its own DataSource, destroyed once
// it has answered, so nothing piles up here.
//
// Each Panel Colorizer still keeps a long-lived DataSource, which gains one property per distinct
// command NAME. So: give repeating commands (polls) a fixed name, and run commands whose arguments
// change every time (a colour, a wallpaper, a window id) with exec(): it writes the arguments to a file
// ($XDG_RUNTIME_DIR, a rotation of 8 names per tag; plasmashell runs with QML_XHR_ALLOW_FILE_WRITE=1)
// and runs ~/.config/plasma-rice/bin/run-argv.py on it, so the names repeat. The answer comes as for
// connectSource, with the source ending in "#<tag> <n>".
QtObject {
    id: shell

    signal newData(string source, var data)

    readonly property string home: ShellHost.home
    readonly property string runtime: ShellHost.runtime

    function connectSource(source) {
        ShellHost.run(source, shell)
    }
    function disconnectSource(source) {}

    function exec(tag, argv) {
        ShellHost.exec(tag, argv, shell)
    }
}
