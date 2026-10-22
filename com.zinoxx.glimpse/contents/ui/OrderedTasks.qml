import QtQuick
import org.kde.taskmanager as TaskManager
import org.kde.kitemmodels as KItemModels

// Every window of every screen in one order (by app name, or most recent first): one row per window for
// the resting strip, one row per app for the opened band (an app with several windows is a group).
// Glimpse makes one, for its order; ScreenTasks does the same per screen for the "by screen" order.
QtObject {
    id: ot

    required property int sortMode          // TasksModel.SortAlpha | SortLastActivated
    signal appsMoved(var roles)             // a window joined or left an app, or an app's data changed

    readonly property TaskManager.TasksModel tasks: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: ot.sortMode
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false             // on Wayland minimized windows report IsHidden
    }
    readonly property KItemModels.KSortFilterProxyModel windows: KItemModels.KSortFilterProxyModel {
        sourceModel: ot.tasks
        filterRowCallback: (row, parent) => ot.tasks.data(ot.tasks.index(row, 0, parent), TaskManager.AbstractTasksModel.IsWindow) === true
    }

    readonly property TaskManager.TasksModel appTasks: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        sortMode: ot.sortMode
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
        // a window joining or leaving a group changes no row of the proxy: the icons re-read their state
        onDataChanged: (topLeft, bottomRight, roles) => ot.appsMoved(roles)
        onRowsInserted: ot.appsMoved([])
        onRowsRemoved: ot.appsMoved([])
    }
    readonly property KItemModels.KSortFilterProxyModel apps: KItemModels.KSortFilterProxyModel {
        sourceModel: ot.appTasks
        filterRowCallback: (row, parent) => {
            const i = ot.appTasks.index(row, 0, parent)
            return ot.appTasks.data(i, TaskManager.AbstractTasksModel.IsWindow) === true
                || ot.appTasks.data(i, TaskManager.AbstractTasksModel.IsGroupParent) === true
        }
    }
}
