.pragma library
// The session's actions, one list for the session menu and the launcher's hero card. Log out, restart and
// shut down open the rice logout screen (org.kde.LogoutPrompt), the one confirmation every launcher uses,
// so a stray click can't end the session. tone: the colour a control lights up in (the calm ones the
// screen's accents, the ones that end the session warm).
//
//   import "Rice/SessionActions.js" as Session      Session.pick(["lock", "sleep"]), a.tip, a.cmd

var PROMPT = "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.";

var ALL = [
    { id: "lock",     icon: "lock",               label: "Lock",      tone: "primary",   cmd: "loginctl lock-session" },
    { id: "sleep",    icon: "bedtime",            label: "Sleep",     tone: "tertiary",  cmd: "systemctl suspend" },
    { id: "logout",   icon: "logout",             label: "Log out",   tone: "secondary", cmd: PROMPT + "promptLogout", confirms: true },
    { id: "reboot",   icon: "restart_alt",        label: "Restart",   tone: "warn",      cmd: PROMPT + "promptReboot", confirms: true },
    { id: "shutdown", icon: "power_settings_new", label: "Shut down", tone: "bad",       cmd: PROMPT + "promptShutDown", confirms: true },
].map(function (a) { a.tip = a.label + (a.confirms ? "…" : ""); return a; });

// the actions with these ids, in the list's order (all of them without ids)
function pick(ids) {
    return ids ? ALL.filter(function (a) { return ids.indexOf(a.id) >= 0; }) : ALL;
}
