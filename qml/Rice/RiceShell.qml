import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Runs shell commands for the rice widgets, with the API of the executable DataSource it replaces, so
// a widget only swaps the declaration: connectSource(cmd) runs cmd, newData(cmd, data) answers with
// data["stdout"], data["stderr"] and data["exit code"], disconnectSource() is a no-op.
//
//   RiceShell { id: sh; onNewData: (source, data) => ... }      sh.connectSource("cmd #tag")
//
// Why not one long-lived DataSource per widget: the executable engine is shared by all of plasmashell,
// and every DataSource bound to it "clears" each finished command from its data map, which ADDS that
// name to the map and rebuilds the map's metaobject (Plasma5Support::DataSource::removeSource ->
// QQmlPropertyMap::clear). So a long-lived DataSource gains one property for every command any widget
// runs, each command costs (DataSources x commands so far), and after two hours a wallpaper change
// froze plasmashell for ~10 s (2026-10-16). Here each command gets its own DataSource, destroyed once
// it has answered, so nothing piles up.
//
// Give repeating commands (polls) a fixed name, no Date.now(): each Panel Colorizer keeps a long-lived
// DataSource of its own, which still gains one property per distinct name.
QtObject {
    id: shell

    signal newData(string source, var data)

    function connectSource(source) {
        runner.createObject(shell).connectSource(source)
    }
    function disconnectSource(source) {}

    readonly property Component runner: Component {
        P5Support.DataSource {
            id: ds
            engine: "executable"
            onNewData: (source, data) => {
                shell.newData(source, data)
                ds.disconnectSource(source)
                ds.destroy()
            }
        }
    }
}
