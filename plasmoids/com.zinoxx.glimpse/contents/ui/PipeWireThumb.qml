import QtQuick
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager
import "Rice"

// A live picture of one window, streamed by KWin over PipeWire for as long as this item exists
// (the stock task manager's tooltip does the same). Loaded through a Loader, so a system without
// PipeWire only loses the picture.
PipeWire.PipeWireSourceItem {
    id: pw
    property string uuid
    nodeId: request.nodeId
    opacity: ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }

    TaskManager.ScreencastingRequest {
        id: request
        uuid: pw.uuid
    }
}
