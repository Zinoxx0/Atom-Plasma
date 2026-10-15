import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_showStrip: showStrip.checked
    property alias cfg_stripHeight: stripHeight.value
    property alias cfg_hoverDelay: hoverDelay.value
    property alias cfg_dwellDelay: dwellDelay.value
    property alias cfg_showNames: showNames.checked
    property alias cfg_thumbnails: thumbnails.checked
    property alias cfg_showMedia: showMedia.checked
    property string cfg_order
    property string cfg_glimpseStyle
    property string cfg_launcherMark

    component Choice: QQC2.ComboBox {
        id: box
        property string value
        signal picked(string v)
        textRole: "text"
        valueRole: "value"
        // indexOfValue() only works once the model is in, so sync after completion and on every change
        function sync() { currentIndex = Math.max(0, indexOfValue(value)) }
        Component.onCompleted: sync()
        onValueChanged: sync()
        onModelChanged: sync()
        onActivated: picked(currentValue)
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showStrip
            Kirigami.FormData.label: i18n("Top strip:")
            text: i18n("Show the window strip at the top of this screen")
        }
        QQC2.SpinBox {
            id: stripHeight
            Kirigami.FormData.label: i18n("Strip height (px):")
            from: 3
            to: 16
        }
        Choice {
            Kirigami.FormData.label: i18n("Strip at rest:")
            model: [{ text: i18n("Pills"), value: "pills" }, { text: i18n("Hairline"), value: "hairline" }]
            value: cfg_glimpseStyle
            onPicked: v => cfg_glimpseStyle = v
        }
        Choice {
            Kirigami.FormData.label: i18n("Order:")
            model: [{ text: i18n("Alphabetical (icons stay put)"), value: "alpha" }, { text: i18n("By screen, left to right"), value: "screen" }, { text: i18n("Most recent first"), value: "recent" }]
            value: cfg_order
            onPicked: v => cfg_order = v
        }
        QQC2.CheckBox {
            id: showNames
            Kirigami.FormData.label: i18n("Open strip:")
            text: i18n("Show app names next to icons")
        }
        QQC2.CheckBox {
            id: thumbnails
            text: i18n("Live window thumbnails under a hovered app")
        }
        QQC2.CheckBox {
            id: showMedia
            text: i18n("Media controls on the right while something plays")
        }
        QQC2.SpinBox {
            id: hoverDelay
            Kirigami.FormData.label: i18n("Open after hovering (ms):")
            from: 0
            to: 1500
            stepSize: 50
        }
        QQC2.SpinBox {
            id: dwellDelay
            Kirigami.FormData.label: i18n("Fullscreen: hold at the top edge (ms):")
            from: 100
            to: 3000
            stepSize: 100
        }
        Choice {
            Kirigami.FormData.label: i18n("Running apps on the bar:")
            model: [{ text: i18n("Dots"), value: "dots" }, { text: i18n("Glow"), value: "glow" }, { text: i18n("Underline"), value: "underline" }]
            value: cfg_launcherMark
            onPicked: v => cfg_launcherMark = v
        }
    }
}
