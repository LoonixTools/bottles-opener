#!/usr/bin/env python3
#
# Lists the bottles and programs of one Bottles installation, and the file
# types each program registered in its bottle's registry. That is how Windows
# knows them: extension -> ProgID -> open command, icon and description.
#
# Runs on the host, or inside the Bottles Flatpak fed through stdin, so it only
# needs what Bottles itself needs: Python and PyYAML.
#
# Usage: scan.py <data home> [cache dir]
#
# Output, one record per line, fields separated by \x1f:
#   R <bottles directory>
#   B <bottle name> <bottle directory> <bottle.yml>
#   P <bottle name> <program id> <program name> <windows path> <icon>
#   A <bottle name> <program id> <ext> <args> <icon file> <icon index> <description>
#
# Copyright (C) 2026 Felitendo
# SPDX-License-Identifier: GPL-3.0-or-later

import hashlib
import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit(3)

LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
SEP = "\x1f"
CACHE_VERSION = 2

EXT_RE = re.compile(r"^[a-z0-9][a-z0-9_+-]{0,31}$")

# Registered by half of all installers, and never a document.
SKIP_EXTS = {
    "exe", "dll", "lnk", "bat", "cmd", "com", "msi", "msp", "scr", "pif",
    "url", "cpl", "sys", "ocx", "drv", "reg", "inf", "ini", "cab",
}


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return yaml.load(f, Loader=LOADER)
    except (OSError, UnicodeDecodeError, yaml.YAMLError):
        return None


def field(value):
    text = "" if value is None else str(value)
    for ch in ("\n", "\r", "\t", SEP):
        text = text.replace(ch, " ")
    return text


def emit(*values):
    sys.stdout.write(SEP.join(field(v) for v in values) + "\n")


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

def _unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "x":
                m = re.match(r"[0-9a-fA-F]{1,4}", s[i + 2:])
                if m:
                    out.append(chr(int(m.group(0), 16)))
                    i += 2 + len(m.group(0))
                    continue
            out.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _string(raw):
    """A value's text, for the string kinds; None for anything else."""
    if raw.startswith('"') and raw.endswith('"'):
        return _unescape(raw[1:-1])
    if raw.startswith('str(2):"') and raw.endswith('"'):
        return _unescape(raw[8:-1])
    if raw.startswith("hex(2):"):
        try:
            data = bytes(int(b, 16) for b in raw[7:].replace(" ", "").split(",") if b)
            return data.decode("utf-16-le").rstrip("\0")
        except ValueError:
            return None
    return None


def read_classes(path):
    """Software\\Classes of one hive: {lowercase subkey: {lowercase name: text}}."""
    classes = {}
    prefix = "software\\classes\\"
    current = None
    pending = None

    try:
        f = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return classes

    with f:
        for line in f:
            line = line.rstrip("\n")

            # hex values run on over lines ending in a backslash
            if pending is not None:
                pending[1] += line.strip().rstrip("\\")
                if not line.endswith("\\"):
                    name, raw = pending
                    pending = None
                    text = _string(raw)
                    if current is not None and text is not None:
                        classes.setdefault(current, {})[name] = text
                continue

            if line.startswith("["):
                end = line.rfind("]")
                key = _unescape(line[1:end]).lower() if end > 0 else ""
                current = key[len(prefix):] if key.startswith(prefix) else None
                # A key exists even with no values, and so do its parents.
                if current:
                    parts = current.split("\\")
                    for n in range(1, len(parts) + 1):
                        classes.setdefault("\\".join(parts[:n]), {})
                continue

            if current is None or not line or line[0] not in '@"':
                continue

            if line.startswith("@="):
                name, raw = "", line[2:]
            else:
                m = re.match(r'"((?:[^"\\]|\\.)*)"=(.*)$', line)
                if not m:
                    continue
                name, raw = _unescape(m.group(1)).lower(), m.group(2)

            if raw.startswith("hex(2):") and raw.endswith("\\"):
                pending = [name, raw.rstrip("\\")]
                continue

            text = _string(raw)
            if text is not None:
                classes.setdefault(current, {})[name] = text

    return classes


def expand(text, users):
    """The environment variables installers put into paths."""
    user = f"C:\\users\\{users}"
    table = {
        "programfiles": "C:\\Program Files",
        "programw6432": "C:\\Program Files",
        "programfiles(x86)": "C:\\Program Files (x86)",
        "commonprogramfiles": "C:\\Program Files\\Common Files",
        "commonprogramw6432": "C:\\Program Files\\Common Files",
        "commonprogramfiles(x86)": "C:\\Program Files (x86)\\Common Files",
        "systemroot": "C:\\windows",
        "windir": "C:\\windows",
        "systemdrive": "C:",
        "programdata": "C:\\ProgramData",
        "allusersprofile": "C:\\ProgramData",
        "public": "C:\\users\\Public",
        "userprofile": user,
        "appdata": user + "\\AppData\\Roaming",
        "localappdata": user + "\\AppData\\Local",
    }
    return re.sub(
        r"%([^%]+)%",
        lambda m: table.get(m.group(1).lower(), m.group(0)),
        text,
    )


def split_command(cmd):
    """(executable, rest) of a command line."""
    cmd = cmd.strip()
    if cmd.startswith('"'):
        end = cmd.find('"', 1)
        if end < 0:
            return cmd[1:], ""
        return cmd[1:end], cmd[end + 1:].strip()
    m = re.match(r"(.*?\.(?:exe|com|bat|cmd))(?:\s+(.*))?$", cmd, re.I)
    if m:
        return m.group(1), (m.group(2) or "").strip()
    exe, _, rest = cmd.partition(" ")
    return exe, rest.strip()


def to_unix(bottle_dir, winpath):
    """A Windows path inside the bottle, found case-insensitively like Windows would."""
    winpath = winpath.strip().strip('"')
    if winpath.startswith("/"):
        return winpath if os.path.exists(winpath) else None
    m = re.match(r"^([A-Za-z]):[\\/]*(.*)$", winpath)
    if not m:
        return None

    path = os.path.realpath(os.path.join(bottle_dir, "dosdevices", m.group(1).lower() + ":"))
    for part in re.split(r"[\\/]+", m.group(2)):
        if not part:
            continue
        candidate = os.path.join(path, part)
        if not os.path.exists(candidate):
            try:
                lower = part.lower()
                match = next(e for e in os.listdir(path) if e.lower() == lower)
            except (OSError, StopIteration):
                return None
            candidate = os.path.join(path, match)
        path = candidate
    return path


def registered_types(bottle_dir, users):
    """{ext: (exe, args, icon file, icon index, description)} from both hives."""
    system = read_classes(os.path.join(bottle_dir, "system.reg"))
    user = read_classes(os.path.join(bottle_dir, "user.reg"))

    def values(key):
        merged = dict(system.get(key, {}))
        merged.update(user.get(key, {}))
        return merged

    def default(key):
        return values(key).get("", "").strip()

    def has(key):
        return key in system or key in user

    keys = set(system) | set(user)
    result = {}

    for key in keys:
        if not key.startswith(".") or "\\" in key:
            continue
        ext = key[1:]
        if not EXT_RE.match(ext) or ext in SKIP_EXTS:
            continue

        progid = default(key).lower()
        if not progid or not has(progid):
            continue
        curver = default(progid + "\\curver").lower()
        if curver and has(curver):
            progid = curver

        # The default verb, else open, else any.
        verb = default(progid + "\\shell").split(",")[0].strip().lower()
        if not verb or not has(f"{progid}\\shell\\{verb}\\command"):
            verb = "open"
        command = default(f"{progid}\\shell\\{verb}\\command")
        if not command:
            verbs = sorted(
                k for k in keys
                if k.startswith(progid + "\\shell\\") and k.endswith("\\command")
            )
            command = default(verbs[0]) if verbs else ""
        if not command:
            continue

        exe, args = split_command(expand(command, users))

        icon_file, icon_index = "", "0"
        icon = expand(default(progid + "\\defaulticon"), users).strip()
        if icon and "%1" not in icon:
            icon = icon.strip('"')
            m = re.match(r'^"?(.*?)"?\s*,\s*(-?\d+)$', icon)
            if m:
                icon, icon_index = m.group(1), m.group(2)
            icon_file = to_unix(bottle_dir, icon) or ""

        desc = ""
        for candidate in (values(progid).get("friendlytypename", ""), default(progid)):
            candidate = candidate.strip()
            if candidate and not candidate.startswith("@"):
                desc = candidate
                break

        result[ext] = (exe, args, icon_file, icon_index, desc)

    return result


def cached_types(bottle_dir, users, cache_dir):
    """registered_types, kept across runs until either hive changes."""
    stamp = []
    for hive in ("system.reg", "user.reg"):
        try:
            st = os.stat(os.path.join(bottle_dir, hive))
            stamp.append([st.st_size, st.st_mtime_ns])
        except OSError:
            stamp.append(None)

    cache = None
    if cache_dir:
        name = hashlib.sha1(bottle_dir.encode()).hexdigest()[:16] + ".json"
        cache = os.path.join(cache_dir, name)
        try:
            with open(cache, encoding="utf-8") as f:
                data = json.load(f)
            if data.get("version") == CACHE_VERSION and data.get("stamp") == stamp:
                return {k: tuple(v) for k, v in data["types"].items()}
        except (OSError, ValueError, KeyError, AttributeError):
            pass

    types = registered_types(bottle_dir, users)

    if cache:
        try:
            os.makedirs(cache_dir, exist_ok=True)
            tmp = cache + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump({"version": CACHE_VERSION, "stamp": stamp, "types": types}, f)
            os.replace(tmp, cache)
        except OSError:
            pass

    return types


def windows_user(bottle_dir):
    try:
        names = os.listdir(os.path.join(bottle_dir, "drive_c", "users"))
    except OSError:
        return "user"
    names = [n for n in names if n.lower() not in ("public", "default", "default user", "all users")]
    return sorted(names)[0] if names else "user"


# ---------------------------------------------------------------------------
# Bottles
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        return 2

    cache_dir = sys.argv[2] if len(sys.argv) > 2 else ""
    base = os.path.join(sys.argv[1], "bottles")
    root = os.path.join(base, "bottles")

    data = load(os.path.join(base, "data.yml"))
    if isinstance(data, dict):
        custom = data.get("custom_bottles_path")
        if (
            isinstance(custom, str)
            and custom
            and not ("/run/user/" in custom and "/doc/" in custom)
            and os.path.isdir(custom)
            and os.access(custom, os.W_OK)
        ):
            root = custom

    emit("R", root)

    try:
        entries = sorted(os.listdir(root))
    except OSError:
        return 0

    for entry in entries:
        bottle_dir = os.path.join(root, entry)
        if not os.path.isdir(bottle_dir):
            continue

        config_path = os.path.join(bottle_dir, "bottle.yml")
        placeholder = os.path.join(bottle_dir, "placeholder.yml")
        if os.path.exists(placeholder):
            target = load(placeholder)
            if not isinstance(target, dict) or not target.get("Path"):
                continue
            bottle_dir = str(target["Path"])
            config_path = os.path.join(bottle_dir, "bottle.yml")

        config = load(config_path)
        if not isinstance(config, dict) or config.get("Environment") == "Steam":
            continue

        name = config.get("Name") or entry
        emit("B", name, bottle_dir, config_path)

        programs = config.get("External_Programs") or {}
        if not isinstance(programs, dict):
            continue

        listed = []
        for key, program in programs.items():
            if not isinstance(program, dict) or program.get("removed"):
                continue
            path = program.get("path")
            if not path:
                continue
            listed.append((
                str(program.get("name") or program.get("executable") or key),
                str(program.get("id") or key),
                str(path),
                program.get("icon") or "",
            ))
        listed.sort(key=lambda p: p[0].lower())

        for prog_name, prog_id, path, icon in listed:
            emit("P", name, prog_id, prog_name, path, icon)

        if not listed:
            continue

        # Which program each registered type belongs to: by its path, as
        # Windows spells it or as it is on disk, and by file name when that
        # names exactly one program.
        by_path, by_real, by_base = {}, {}, {}
        for _, prog_id, path, _ in listed:
            by_path[path.lower().replace("/", "\\")] = prog_id
            real = to_unix(bottle_dir, path)
            if real:
                by_real[os.path.realpath(real)] = prog_id
            base_name = re.split(r"[\\/]", path)[-1].lower()
            by_base.setdefault(base_name, []).append(prog_id)

        types = cached_types(bottle_dir, windows_user(bottle_dir), cache_dir)
        for ext in sorted(types):
            exe, args, icon_file, icon_index, desc = types[ext]
            prog_id = by_path.get(exe.lower().replace("/", "\\"))
            if not prog_id:
                real = to_unix(bottle_dir, exe)
                prog_id = by_real.get(os.path.realpath(real)) if real else None
            if not prog_id:
                hits = by_base.get(re.split(r"[\\/]", exe)[-1].lower(), [])
                prog_id = hits[0] if len(hits) == 1 else None
            if prog_id:
                emit("A", name, prog_id, ext, args, icon_file, icon_index, desc)

    return 0


if __name__ == "__main__":
    sys.exit(main())
