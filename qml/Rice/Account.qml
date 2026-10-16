import QtQuick
import org.kde.coreaddons as KCoreAddons

// Who is logged in, named the same way everywhere (session, launcher, splash): the first word
// of the account's full name (the GECOS field, via KUser), else the login name.
//
//   Account { id: me }   then me.displayName ("Samir"), me.initial, me.loginName, me.host
QtObject {
    property KCoreAddons.KUser user: KCoreAddons.KUser {}

    readonly property string loginName: user.loginName
    readonly property string fullName: user.fullName
    readonly property string displayName: fullName.trim().split(/[\s,]+/)[0] || loginName
    readonly property string initial: displayName ? displayName[0].toUpperCase() : "?"
    readonly property string host: user.host
    readonly property url face: user.faceIconUrl
}
