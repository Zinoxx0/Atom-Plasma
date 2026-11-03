import QtQuick
import QtQuick.Layouts
import "../../qml/Rice"

// A stand-in for org.kde.panel: its GridLayout of applet containers (each with `applet`, as Plasma's
// AppletContainer), a Repeater among them as in the real panel, and BarFit run from one of the applets.
// Prints "fit <room> <step> <needs>" for each bar width in `widths`, then quits (tests/test_barfit.py).
Item {
    id: top
    width: 1000; height: 50
    component Applet: Item {
        property var riceFit
        property real minW: 0
        property real prefW: 0
        Layout.minimumWidth: minW
        Layout.preferredWidth: prefW
    }
    component Box: Item {
        id: box
        required property Item applet
        property bool wantsToFillWidth: applet.Layout.fillWidth
        Layout.fillWidth: true
        Layout.minimumWidth: applet.Layout.minimumWidth
        Layout.preferredWidth: Math.max(applet.Layout.preferredWidth, Layout.minimumWidth)
        Layout.maximumWidth: wantsToFillWidth ? 100000 : Layout.preferredWidth
        Component.onCompleted: applet.parent = box
    }
    Applet { id: launcher; minW: 60; prefW: 60 }
    Applet { id: pins; riceFit: [500, 500, 500, 120]; minW: 500; prefW: 500 }
    Applet { id: stretch; minW: 1; prefW: 0; Layout.fillWidth: true }
    Applet { id: claude; riceFit: [200, 200, 120]; minW: 200; prefW: 200 }
    Applet { id: system; riceFit: [300, 180, 180, 180, 150]; minW: 300; prefW: 300 }
    Applet { id: tray; minW: 150; prefW: 150 }
    Applet { id: making; riceFit: [] }                  // a rice widget still making its representation
    Applet { id: hidden; minW: 400; prefW: 400 }        // a hidden widget takes no room
    GridLayout {
        id: grid
        width: top.width
        columnSpacing: 4
        rows: 1
        flow: GridLayout.LeftToRight
        Box { applet: launcher } Box { applet: pins } Box { applet: stretch } Box { applet: claude }
        Box { applet: system } Box { applet: tray } Box { applet: making } Box { applet: hidden; visible: false }
        Repeater { model: 0; Item {} }
    }
    BarFit { id: fit; widget: system }
    Timer {
        interval: 30; running: true; repeat: true
        property var widths: [1600, 1235, 1234, 1100, 1000, 640, 600, 2000]
        property int i: 0
        onTriggered: {
            if (i > 0) console.warn("fit", fit.room, fit.step, JSON.stringify(fit.needs))
            if (i >= widths.length) { Qt.quit(); return }
            top.width = widths[i++]
        }
    }
}
