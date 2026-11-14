.pragma library
// The session's actions, one list for the session menu, the launcher's hero card and the power overlay.
// Log out, restart and shut down must be confirmed: `cmd` opens the rice logout screen (org.kde.LogoutPrompt),
// the one confirmation every launcher uses, so a stray click can't end the session; the power overlay
// confirms them itself (a countdown ring, Esc cancels) and then runs `now` (ksmserver's org.kde.Shutdown:
// apps are asked to close as usual). `doing` is what the countdown says. tone: the colour a control lights
// up in (the calm ones the screen's accents, the ones that end the session warm).
//
//   import "Rice/SessionActions.js" as Session      Session.pick(["lock", "sleep"]), a.tip, a.cmd

var PROMPT = "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.";
var NOW = "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.";

var ALL = [
    { id: "lock",     icon: "lock",               label: "Lock",      tone: "primary",   cmd: "loginctl lock-session" },
    { id: "sleep",    icon: "bedtime",            label: "Sleep",     tone: "tertiary",  cmd: "systemctl suspend" },
    { id: "logout",   icon: "logout",             label: "Log out",   tone: "secondary", cmd: PROMPT + "promptLogout", confirms: true, now: NOW + "logout", doing: "Logging out" },
    { id: "reboot",   icon: "restart_alt",        label: "Restart",   tone: "warn",      cmd: PROMPT + "promptReboot", confirms: true, now: NOW + "logoutAndReboot", doing: "Restarting" },
    { id: "shutdown", icon: "power_settings_new", label: "Shut down", tone: "bad",       cmd: PROMPT + "promptShutDown", confirms: true, now: NOW + "logoutAndShutdown", doing: "Shutting down" },
].map(function (a) { a.tip = a.label + (a.confirms ? "…" : ""); return a; });

// the actions with these ids, in the list's order (all of them without ids)
function pick(ids) {
    return ids ? ALL.filter(function (a) { return ids.indexOf(a.id) >= 0; }) : ALL;
}
