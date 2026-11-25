pragma Singleton
import QtQuick
import QtCore
import org.kde.plasma.plasma5support as P5Support

// Process-lifetime host for RiceShell commands so unloading a page or closing the launcher right after
// picking a wallpaper or preset never destroys a running QProcess mid-flight (leaving half-applied themes).
QtObject {
    id: host

    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    readonly property string runtime: String(StandardPaths.writableLocation(StandardPaths.RuntimeLocation)).replace(/^file:\/\//, "")
    property int slot: 0

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function run(source, owner) {
        runner.createObject(host, { owner: owner }).connectSource(source)
    }

    function exec(tag, argv, owner) {
        const n = slot = (slot + 1) % 8
        const file = runtime + "/atom-cmd-" + tag + "-" + n + ".json"
        const named = 'python3 "$HOME/.config/plasma-rice/bin/run-argv.py" ' + q(file) + " #" + tag + " " + n
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => { if (x.readyState === XMLHttpRequest.DONE) host.run(named, owner) }
        try {
            x.open("PUT", "file://" + file)
            x.send(JSON.stringify(argv.map(String)))
        } catch (e) {
            run(argv.map(q).join(" ") + " #" + tag + " " + n, owner)
        }
    }

    readonly property Component runner: Component {
        P5Support.DataSource {
            id: ds
            property RiceShell owner: null
            engine: "executable"
            onNewData: (source, data) => {
                if (ds.owner) ds.owner.newData(source, data)
                ds.disconnectSource(source)
                ds.destroy()
            }
        }
    }
}
