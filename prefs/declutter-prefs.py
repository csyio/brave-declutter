#!/usr/bin/env python3
"""Hide leftover Brave toolbar buttons and new-tab items by editing the
profile's Preferences file.

Brave must be fully closed. A timestamped backup is written next to the
file before any change. --undo first keeps a copy of the current file
(Preferences.bak-declutter-preundo-<time>), then restores the newest backup
made by this script and marks it as used (.restored), so running --undo again
steps back to the next older backup. Standard library only, no network
access, no elevated rights (do not run it with sudo).
"""

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

# Dotted path under the top-level "brave" object -> value.
BRAVE_KEYS = {
    "show_brave_rewards_button": False,
    "rewards.show_brave_rewards_button_in_location_bar": False,
    "ai_chat.show_toolbar_button": False,
    "wallet.show_wallet_icon_on_toolbar": False,
    "brave_vpn.show_button": False,
    "today.should_show_toolbar_button": False,
    "show_side_panel_button": False,
    "sidebar.sidebar_show_option": 3,  # 3 = never show the sidebar
    "new_tab_page.show_branded_background_image": False,  # sponsored images
    "new_tab_page.show_stats": False,
    "new_tab_page.show_brave_news": False,
}

BACKUP_MARKER = ".bak-declutter-"
PREUNDO_MARKER = ".bak-declutter-preundo-"
# Matches only real backups: not "preundo" copies and not ".restored" ones.
BACKUP_RE = re.compile(r"\.bak-declutter-(\d{8}-\d{6})(?:-(\d+))?$")


def default_profile_dir():
    system = platform.system()
    if system == "Darwin":
        return (Path.home() / "Library/Application Support/BraveSoftware"
                / "Brave-Browser/Default")
    if system == "Linux":
        return Path.home() / ".config/BraveSoftware/Brave-Browser/Default"
    if system == "Windows":
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise SystemExit("LOCALAPPDATA is not set; use --profile-dir.")
        return (Path(local) / "BraveSoftware/Brave-Browser"
                / "User Data/Default")
    raise SystemExit("Unsupported OS %r; use --profile-dir." % system)


def brave_is_running():
    system = platform.system()
    try:
        if system == "Windows":
            out = subprocess.run(
                ["tasklist", "/FI", "IMAGENAME eq brave.exe", "/NH"],
                capture_output=True, text=True, check=False).stdout
            return "brave.exe" in out.lower()
        names = ["Brave Browser", "brave", "brave-browser"]
        return any(
            subprocess.run(["pgrep", "-x", n], capture_output=True,
                           check=False).returncode == 0
            for n in names)
    except OSError as exc:
        # Cannot tell; refuse rather than risk corrupting a live profile.
        raise SystemExit("Could not check whether Brave is running (%s). "
                         "Make sure Brave is fully closed, then rerun with "
                         "--skip-running-check." % exc)


def set_dotted(root, dotted, value):
    """Set root["a"]["b"]["c"] = value for "a.b.c", creating dicts."""
    parts = dotted.split(".")
    node = root
    for part in parts[:-1]:
        if not isinstance(node.get(part), dict):
            node[part] = {}
        node = node[part]
    node[parts[-1]] = value


def get_dotted(root, dotted):
    node = root
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def write_atomic_bytes(path, data):
    """Write data to a temp file in the same directory, then os.replace."""
    directory = path.parent
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp",
                               dir=str(directory))
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            shutil.copymode(str(path), tmp)
        except OSError:
            pass
        os.replace(tmp, str(path))
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def unique_name(prefs, marker, stamp):
    """Return a not-yet-existing sibling path Preferences<marker><stamp>[-n]."""
    path = prefs.with_name(prefs.name + marker + stamp)
    n = 1
    while path.exists() or path.with_name(path.name + ".restored").exists():
        n += 1
        path = prefs.with_name("%s%s%s-%d" % (prefs.name, marker, stamp, n))
    return path


def list_backups(prefs):
    """Real backups made by apply, oldest first. Excludes preundo copies and
    backups already consumed by --undo (.restored)."""
    found = []
    for path in prefs.parent.glob(prefs.name + BACKUP_MARKER + "*"):
        match = BACKUP_RE.fullmatch(path.name[len(prefs.name):])
        if match and path.is_file():
            found.append((match.group(1), int(match.group(2) or 1), path))
    found.sort(key=lambda item: item[:2])
    return [item[2] for item in found]


def same_value(old, new):
    # bool is a subclass of int in Python: keep False and 0 apart.
    return old is not None and type(old) is type(new) and old == new


def do_apply(prefs):
    raw = prefs.read_bytes()
    try:
        data = json.loads(raw.decode("utf-8"))
    except ValueError as exc:  # includes UnicodeDecodeError
        print("Error: %s is not valid JSON (%s). Nothing was changed."
              % (prefs, exc), file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print("Error: unexpected Preferences layout. Nothing was changed.",
              file=sys.stderr)
        return 1

    brave = data.get("brave")
    if not isinstance(brave, dict):
        brave = {}
    pending = [(dotted, value) for dotted, value in BRAVE_KEYS.items()
               if not same_value(get_dotted(brave, dotted), value)]
    if not pending:
        print("Already applied, nothing to do.")
        return 0

    if not isinstance(data.get("brave"), dict):
        data["brave"] = brave
    try:
        for dotted, value in BRAVE_KEYS.items():
            was_set = same_value(get_dotted(brave, dotted), value)
            set_dotted(brave, dotted, value)
            print("  brave.%s = %s (%s)" % (dotted, json.dumps(value),
                                            "already set" if was_set
                                            else "set"))
        out = json.dumps(data, separators=(",", ":"),
                         ensure_ascii=False).encode("utf-8")
    except (ValueError, TypeError) as exc:
        print("Error: could not serialize Preferences (%s). Nothing was "
              "changed." % exc, file=sys.stderr)
        return 1

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = unique_name(prefs, BACKUP_MARKER, stamp)
    shutil.copy2(str(prefs), str(backup))
    print("Backup written: %s" % backup)
    write_atomic_bytes(prefs, out)
    print("Done. Start Brave again to see the changes.")
    return 0


def do_undo(prefs):
    backups = list_backups(prefs)
    if not backups:
        print("Error: no backup made by this script found next to %s."
              % prefs, file=sys.stderr)
        return 1
    latest = backups[-1]
    restored = latest.with_name(latest.name + ".restored")
    if restored.exists():
        print("Error: %s already exists; remove or rename it and try again."
              % restored.name, file=sys.stderr)
        return 1
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    preundo = unique_name(prefs, PREUNDO_MARKER, stamp)
    shutil.copy2(str(prefs), str(preundo))
    write_atomic_bytes(prefs, latest.read_bytes())
    os.replace(str(latest), str(restored))
    print("Restored %s from %s" % (prefs, latest.name))
    print("Your settings from before the undo are kept in %s" % preundo)
    print("Backup renamed to %s; run --undo again to step back to an older "
          "backup." % restored.name)
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Hide leftover Brave toolbar and new-tab clutter by "
                    "editing the profile Preferences file.")
    parser.add_argument("--profile-dir", type=Path,
                        help="profile folder containing Preferences "
                             "(default: the Default profile of Brave)")
    parser.add_argument("--undo", action="store_true",
                        help="restore the newest backup made by this script "
                             "(a copy of the current file is kept first)")
    parser.add_argument("--skip-running-check", action="store_true",
                        help="only if the running check itself fails and Brave "
                             "is definitely closed")
    args = parser.parse_args()

    if hasattr(os, "geteuid") and os.geteuid() == 0:
        print("Do not run with sudo; this script edits your own profile.",
              file=sys.stderr)
        return 1

    profile = args.profile_dir or default_profile_dir()
    prefs = profile / "Preferences"
    if not prefs.is_file():
        print("Error: %s not found. Pass --profile-dir if your profile is "
              "elsewhere." % prefs, file=sys.stderr)
        return 1

    if not args.skip_running_check and brave_is_running():
        print("Error: Brave is running. Quit it completely (including "
              "background processes) and run this again.", file=sys.stderr)
        return 2

    try:
        return do_undo(prefs) if args.undo else do_apply(prefs)
    except (OSError, ValueError) as exc:  # ValueError includes UnicodeError
        print("Error: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
