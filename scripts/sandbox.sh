#!/usr/bin/env bash
# Runs the checkout against a throwaway XDG tree. Reads the real bottles, writes nowhere else.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
box="${BO_SANDBOX:-${TMPDIR:-/tmp}/bottles-opener-sandbox}"

# The real bottles, resolved before the XDG dirs are pointed away.
export BO_NATIVE_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
export BO_FLATPAK_DATA="$HOME/.var/app/com.usebottles.bottles/data"

export XDG_CONFIG_HOME="$box/config" XDG_DATA_HOME="$box/data"
export XDG_STATE_HOME="$box/state" XDG_CACHE_HOME="$box/cache"
export BO_LIBDIR="$root/src/lib" BO_NO_WATCH=1

# Translations, when built.
if [[ -f $root/po/de.mo ]]; then
	mkdir -p "$box/locale/de/LC_MESSAGES"
	cp -f "$root/po/de.mo" "$box/locale/de/LC_MESSAGES/bottles-opener.mo"
	export BO_LOCALEDIR="$box/locale"
fi

mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
exec "$root/src/bottles-opener" "$@"
