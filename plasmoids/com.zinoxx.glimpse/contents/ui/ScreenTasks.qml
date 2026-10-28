import QtQuick
import org.kde.taskmanager as TaskManager
import org.kde.kitemmodels as KItemModels

// The windows on one screen, in the order they were opened (startup placeholders left out):
// one row per window for the resting strip, one row per app for the opened band.
QtObject {
    id: st

    required property var screenInfo        // an entry of Qt.application.screens
    readonly property rect geometry: Qt.rect(screenInfo.virtualX, screenInfo.virtualY, screenInfo.width, screenInfo.height)

    readonly property TaskManager.TasksModel tasks: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        filterByScreen: true
        screenGeometry: st.geometry
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
    }
    readonly property KItemModels.KSortFilterProxyModel windows: KItemModels.KSortFilterProxyModel {
        sourceModel: st.tasks
        filterRowCallback: (row, parent) => st.tasks.data(st.tasks.index(row, 0, parent), TaskManager.AbstractTasksModel.IsWindow) === true
    }

    readonly property TaskManager.TasksModel appTasks: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        sortMode: TaskManager.TasksModel.SortDisabled
        filterByScreen: true
        screenGeometry: st.geometry
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
    }
    readonly property KItemModels.KSortFilterProxyModel apps: KItemModels.KSortFilterProxyModel {
        sourceModel: st.appTasks
        filterRowCallback: (row, parent) => {
            const i = st.appTasks.index(row, 0, parent)
            return st.appTasks.data(i, TaskManager.AbstractTasksModel.IsWindow) === true
                || st.appTasks.data(i, TaskManager.AbstractTasksModel.IsGroupParent) === true
        }
    }
}
