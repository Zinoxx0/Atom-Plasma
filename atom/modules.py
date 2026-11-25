"""Misc Modules registry for Atom Plasma.

Discovers optional, toggleable modules from:
  1. Built-in modules:  <repo>/modules/<id>/module.json
  2. User drop-ins:     ~/.config/atom-plasma/modules/<id>/module.json

Each module can ship a Plasma widget (`plasmoid`), optional systemd units, optional hook setup,
and a declarative `config` schema rendered automatically on the Theme page under "Misc Modules".
Users can add standalone modules (ChatGPT, Grok, Codex, ...) into ~/.config/atom-plasma/modules/
without editing Atom Plasma core.
"""
import json
import subprocess
import sys
from pathlib import Path

from . import caps, util
from .util import HOME, ROOT

BUILTIN_DIR = ROOT / "modules"
USER_DIR = HOME / ".config/atom-plasma/modules"


def _load_manifest(path, builtin):
    try:
        raw = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(raw, dict):
        return None
    mid = str(raw.get("id") or path.parent.name).strip().lower()
    if not mid or not all(c.isalnum() or c in "-_" for c in mid):
        return None
    mdir = path.parent
    plasmoid = str(raw.get("plasmoid") or "").strip()
    plasmoid_path = None
    if plasmoid:
        for cand in (mdir / "plasmoid", mdir / plasmoid, ROOT / "plasmoids" / plasmoid):
            if (cand / "metadata.json").is_file():
                plasmoid_path = cand
                break
    systemd_units = [str(u) for u in (raw.get("systemd") or []) if isinstance(u, str) and u.strip()]
    systemd_paths = []
    if (mdir / "systemd").is_dir():
        systemd_paths = sorted(f for f in (mdir / "systemd").iterdir() if f.suffix in (".service", ".timer"))
    schema = []
    for opt in raw.get("config") or []:
        if not isinstance(opt, dict) or not opt.get("key"):
            continue
        entry = {
            "key": str(opt["key"]),
            "label": str(opt.get("label") or opt["key"]),
            "type": str(opt.get("type") or "bool"),
            "default": opt.get("default"),
            "desc": str(opt.get("desc") or ""),
        }
        if entry["type"] == "choice":
            entry["options"] = [
                {"value": str(o["value"]), "label": str(o.get("label") or o["value"]),
                 "dots": list(o.get("dots") or [])}
                for o in (opt.get("options") or []) if isinstance(o, dict) and "value" in o
            ]
        elif entry["type"] in ("int", "number"):
            entry["min"] = opt.get("min", 0)
            entry["max"] = opt.get("max", 100)
            entry["step"] = opt.get("step", 1)
        schema.append(entry)
    return {
        "id": mid,
        "name": str(raw.get("name") or mid.title()),
        "subtitle": str(raw.get("subtitle") or ""),
        "icon": str(raw.get("icon") or "extension"),
        "accent": str(raw.get("accent") or ""),
        "bar_slot": str(raw.get("bar_slot") or ""),
        "order": int(raw.get("order", 100)),
        "plasmoid": plasmoid,
        "portal_kind": str(raw.get("portal_kind") or ""),
        "desk": bool(raw.get("desk", False)),
        "capabilities": [str(c) for c in (raw.get("capabilities") or []) if isinstance(c, str)],
        "default_enabled": raw.get("default_enabled"),
        "systemd": systemd_units,
        "setup": str(raw.get("setup") or ""),
        "schema": schema,
        "builtin": builtin,
        "dir": str(mdir),
        "plasmoid_path": str(plasmoid_path) if plasmoid_path else "",
        "systemd_paths": [str(p) for p in systemd_paths],
    }


def discover():
    """All discovered modules (built-in + user drop-ins), ordered by (order, id)."""
    by_id = {}
    for root, builtin in ((BUILTIN_DIR, True), (USER_DIR, False)):
        if not root.is_dir():
            continue
        for child in sorted(root.iterdir()):
            mf = child / "module.json"
            if child.is_dir() and mf.is_file():
                mod = _load_manifest(mf, builtin)
                if mod:
                    by_id[mod["id"]] = mod
    return sorted(by_id.values(), key=lambda m: (m["order"], m["id"]))


def get(mod_id):
    return next((m for m in discover() if m["id"] == mod_id), None)


def detected(mod):
    """Whether this machine appears to have what `mod` uses."""
    needs = mod.get("capabilities") or []
    if not needs:
        return True
    f = caps.found()
    return all(f.get(c, False) for c in needs)


def is_enabled(mod_id, cfg=None):
    """Whether module `mod_id` is enabled: explicit modules.<id>.enabled wins; else features.<id> / auto."""
    cfg = util.settings() if cfg is None else cfg
    entry = (cfg.get("modules") or {}).get(mod_id)
    if isinstance(entry, dict) and isinstance(entry.get("enabled"), bool):
        return entry["enabled"]
    if mod_id in caps.FEATURES:
        return caps.feature(mod_id, cfg)
    mod = get(mod_id)
    if not mod:
        return False
    if isinstance(mod.get("default_enabled"), bool):
        return mod["default_enabled"]
    return detected(mod)


def module_config(mod_id, cfg=None):
    """Resolved per-module config dict (manifest defaults overlaid by settings.json modules.<id>.config)."""
    cfg = util.settings() if cfg is None else cfg
    mod = get(mod_id)
    out = {opt["key"]: opt["default"] for opt in (mod["schema"] if mod else [])}
    stored = ((cfg.get("modules") or {}).get(mod_id) or {}).get("config")
    if isinstance(stored, dict):
        for k, v in stored.items():
            out[k] = v
    return out


def bar_modules(slot="meters", cfg=None):
    """Enabled modules placed in `slot`, in display order."""
    cfg = util.settings() if cfg is None else cfg
    return [m for m in discover() if m["bar_slot"] == slot and m["plasmoid"] and is_enabled(m["id"], cfg)]


def all_bar_plasmoids(slot="meters"):
    """Every discovered module plasmoid targeting `slot`, in display order (enabled or not)."""
    return [m["plasmoid"] for m in discover() if m["bar_slot"] == slot and m["plasmoid"]]


def module_units(cfg=None):
    """Systemd user units belonging to enabled modules."""
    cfg = util.settings() if cfg is None else cfg
    out = []
    for m in discover():
        if is_enabled(m["id"], cfg):
            out += m["systemd"]
    return out


def all_module_units():
    """Map of {unit_name: module_id} for all units declared by any module."""
    out = {}
    for m in discover():
        for u in m["systemd"]:
            out[u] = m["id"]
    return out


def state_list(cfg=None):
    """JSON-serializable list of every module with live enabled/detected state and resolved config."""
    cfg = util.settings() if cfg is None else cfg
    out = []
    for m in discover():
        out.append({
            "id": m["id"],
            "name": m["name"],
            "subtitle": m["subtitle"],
            "icon": m["icon"],
            "accent": m["accent"],
            "barSlot": m["bar_slot"],
            "order": m["order"],
            "plasmoid": m["plasmoid"],
            "portalKind": m["portal_kind"],
            "desk": m["desk"],
            "builtin": m["builtin"],
            "dir": m["dir"],
            "detected": detected(m),
            "enabled": is_enabled(m["id"], cfg),
            "config": module_config(m["id"], cfg),
            "schema": m["schema"],
        })
    return out


def _coerce_value(opt, raw):
    kind = opt["type"]
    if kind == "bool":
        if isinstance(raw, bool):
            return raw
        s = str(raw).strip().lower()
        if s in ("true", "1", "on", "yes"):
            return True
        if s in ("false", "0", "off", "no"):
            return False
        raise ValueError(f"{opt['key']} takes true or false")
    if kind == "choice":
        allowed = [o["value"] for o in opt.get("options") or []]
        v = str(raw).strip()
        if allowed and v not in allowed:
            raise ValueError(f"{opt['key']} must be one of: {', '.join(allowed)}")
        return v
    if kind == "int":
        v = int(float(raw))
        return max(int(opt.get("min", v)), min(int(opt.get("max", v)), v))
    if kind == "number":
        v = float(raw)
        return max(float(opt.get("min", v)), min(float(opt.get("max", v)), v))
    return str(raw)


def _sync_units(mod, on):
    for u in mod["systemd"]:
        unit_file = HOME / ".config/systemd/user" / u
        if not unit_file.exists():
            continue
        util.run("systemctl", "--user", "enable" if on else "disable", "--now", u, quiet=True, timeout=15)


def _sync_hooks(mod, on, cfg):
    if mod["id"] == "claude" and on:
        from . import claude
        path = claude.SETTINGS.resolve()
        try:
            new, _ = claude.plan(path.read_text() if path.exists() else "", caps.feature("update_check", cfg))
            if new:
                mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
                util.write_if_changed(path, new)
                path.chmod(mode)
        except (OSError, ValueError):
            pass
    elif mod["id"] == "gemini":
        from . import gemini
        for path in gemini.hook_files():
            try:
                new, _ = gemini.plan(path.read_text() if path.exists() else "", enabled=on)
                if new is not None:
                    util.write_if_changed(path, new)
            except (OSError, ValueError):
                pass
    elif mod.get("setup"):
        script = Path(mod["dir"]) / mod["setup"]
        if script.is_file():
            util.run(str(script), "enable" if on else "disable", quiet=True, timeout=20)


def _refresh_desk(cfg):
    try:
        from . import screens
        p = util.load_json(util.STATE / "palette.json")
        ss = screens.screens(cfg)
        if p and ss:
            screens.apply_screens(ss, cfg, p)
    except Exception as e:
        util.warn("modules: desk refresh skipped: %s", e)


def _ensure_bar_widget(mod, cfg):
    if not mod["plasmoid"] or mod["bar_slot"] != "meters":
        return
    # Link user module plasmoid if not linked yet
    if mod["plasmoid_path"]:
        link = HOME / ".local/share/plasma/plasmoids" / mod["plasmoid"]
        if not link.exists():
            try:
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(Path(mod["plasmoid_path"]))
            except OSError:
                pass
    try:
        from . import panel
        panel.sync_meter_modules(cfg)
    except Exception as e:
        util.warn("modules: bar sync skipped: %s", e)


def set_enabled(mod_id, on, apply_live=True):
    """Enable or disable `mod_id`, persist settings, and sync hooks/systemd/desk/bar."""
    mod = get(mod_id)
    if not mod:
        raise SystemExit(f"unknown module {mod_id!r}")
    util.hold_lock()
    cfg = util.user_settings()
    entry = cfg.setdefault("modules", {}).setdefault(mod_id, {})
    entry["enabled"] = bool(on)
    util.save_settings(cfg)
    full = util.settings()
    if apply_live:
        _sync_units(mod, bool(on))
        _sync_hooks(mod, bool(on), full)
        if mod["desk"]:
            _refresh_desk(full)
        if on:
            _ensure_bar_widget(mod, full)
    return is_enabled(mod_id, full)


def set_option(mod_id, key, raw_value, apply_live=True):
    """Set a single config option on `mod_id`, validated against its manifest schema."""
    mod = get(mod_id)
    if not mod:
        raise SystemExit(f"unknown module {mod_id!r}")
    opt = next((o for o in mod["schema"] if o["key"] == key), None)
    if not opt:
        raise SystemExit(f"module {mod_id!r} has no option {key!r}")
    try:
        val = _coerce_value(opt, raw_value)
    except (ValueError, TypeError) as e:
        raise SystemExit(str(e))
    util.hold_lock()
    cfg = util.user_settings()
    entry = cfg.setdefault("modules", {}).setdefault(mod_id, {})
    entry.setdefault("config", {})[key] = val
    util.save_settings(cfg)
    if apply_live and mod["desk"]:
        _refresh_desk(util.settings())
    return val


def main(args):
    sub = args[0] if args else "list"
    if sub == "list":
        print(json.dumps({"dir": str(USER_DIR), "modules": state_list()}))
    elif sub in ("enable", "disable", "toggle"):
        if len(args) < 2:
            raise SystemExit(f"rice.py modules {sub} <id>")
        mid = args[1]
        on = True if sub == "enable" else False if sub == "disable" else not is_enabled(mid)
        res = set_enabled(mid, on)
        print(json.dumps({"id": mid, "enabled": res}))
    elif sub == "set":
        if len(args) < 4:
            raise SystemExit("rice.py modules set <id> <key> <value>")
        val = set_option(args[1], args[2], args[3])
        print(json.dumps({"id": args[1], "key": args[2], "value": val}))
    else:
        raise SystemExit("rice.py modules list|enable|disable|toggle|set ...")
