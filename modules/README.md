# Atom Plasma Misc Modules

Optional desktop widgets and integrations (such as Claude + Clawd, Gemini, or your own ChatGPT / Grok modules) are discovered from two directories:

1. Built-in modules: `~/.config/plasma-rice/modules/<id>/module.json`
2. User drop-in modules: `~/.config/atom-plasma/modules/<id>/module.json`

## Writing a Standalone Module

Create `~/.config/atom-plasma/modules/<id>/` with:

- `module.json` — manifest describing the module, its plasmoid, optional systemd units, and settings controls rendered automatically in **Theme → Misc Modules**:
  ```json
  {
    "id": "chatgpt",
    "name": "ChatGPT",
    "subtitle": "Codex usage meter",
    "icon": "bolt",
    "accent": "#10a37f",
    "bar_slot": "meters",
    "order": 30,
    "plasmoid": "com.user.chatgptusage",
    "portal_kind": "chatgpt",
    "systemd": ["my-chatgpt-usage.timer"],
    "config": [
      { "key": "alerts", "label": "80% / 95% alerts", "type": "bool", "default": true }
    ]
  }
  ```
- Optional `plasmoid/` folder (containing `metadata.json` and `contents/ui/main.qml`) — symlinked automatically by `rice.py install` to `~/.local/share/plasma/plasmoids/<plasmoid>`.
- Optional `systemd/` folder (`*.service`, `*.timer`) — symlinked automatically to `~/.config/systemd/user/`.
- In your QML plasmoid:
  - Read live toggle & options via `Atom.Prefs`: `Prefs.moduleEnabled("chatgpt", true)` and `Prefs.moduleOpt("chatgpt", "alerts", true)`.
  - Collapse cleanly when disabled by setting `Plasmoid.status: moduleOn ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus` and `Layout.preferredWidth: moduleOn ? ... : 0`.
  - Use `Rice.PortalHost { widget: root; kind: "chatgpt"; screenName: root.myScreenName; popup: root.popup }` — `Atom.Shell` auto-registers any portal `kind` on its morphing glass sheet.
- Tip: if you use T3 Code, live provider caches also live in `~/.t3/caches/` (e.g. `codex.json`, `grok.json`, `antigravity.json`, `claudeAgent.json`).
