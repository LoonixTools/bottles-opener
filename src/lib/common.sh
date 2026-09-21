# shellcheck shell=bash
#
# Paths, translations, output helpers and the change ledger.

BO_VERSION="@VERSION@"
BO_NAME="bottles-opener"
BO_PRETTY="Bottles Opener"

BO_LIBDIR="${BO_LIBDIR:-@LIBDIR@}"
BO_LOCALEDIR="${BO_LOCALEDIR:-@LOCALEDIR@}"

BO_XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
BO_XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
BO_XDG_STATE="${XDG_STATE_HOME:-$HOME/.local/state}"

BO_CONFDIR="${BO_CONFDIR:-${BO_XDG_CONFIG}/${BO_NAME}}"
BO_CONFIG="${BO_CONFIG:-${BO_CONFDIR}/config}"
BO_TYPES="${BO_TYPES:-${BO_CONFDIR}/types}"
BO_STATEDIR="${BO_STATEDIR:-${BO_XDG_STATE}/${BO_NAME}}"
BO_CACHEDIR="${BO_CACHEDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/${BO_NAME}}"

# Launchers, each named bottles-opener-<id>.desktop.
BO_APPDIR="${BO_XDG_DATA}/applications"

# The user's MIME database; update-mime-database compiles packages/.
BO_MIMEDIR="${BO_XDG_DATA}/mime"
BO_MIMEPKG="${BO_MIMEDIR}/packages/${BO_NAME}.xml"

# hicolor: the theme every other theme falls back to.
BO_ICONDIR="${BO_XDG_DATA}/icons/hicolor"

# Default applications. Every desktop reads this one.
BO_MIMEAPPS="${BO_XDG_CONFIG}/mimeapps.list"

# Every change, so `disable` undoes exactly that. See bo_ledger_add.
BO_LEDGER="${BO_STATEDIR}/ledger"

# Which launcher starts what, read by `open`. Exec lines carry only the id:
# no bottle name to quote.
BO_LAUNCHERS="${BO_STATEDIR}/launchers"

# The Windows arguments per launcher and extension, as the registry has them.
BO_COMMANDS="${BO_STATEDIR}/commands"

BO_FLATPAK_ID="com.usebottles.bottles"

# ---------------------------------------------------------------------------
# Translations
# ---------------------------------------------------------------------------

export TEXTDOMAIN="bottles-opener"
export TEXTDOMAINDIR="${BO_LOCALEDIR}"

bo_ui_locale() {
	local l="${BO_UI_LOCALE:-}"

	if [[ -z $l ]]; then
		l="${LC_ALL:-}"
		[[ -z $l ]] && l="${LC_MESSAGES:-}"
		[[ -z $l ]] && l="${LANG:-}"
	fi

	# systemd's file, and Debian's.
	if [[ -z $l ]]; then
		local f
		for f in /etc/locale.conf /etc/default/locale; do
			[[ -r $f ]] || continue
			l="$(sed -n 's/^LANG=//p' "$f" | tr -d '"' | head -n1)"
			[[ -n $l ]] && break
		done
	fi

	printf '%s\n' "${l:-C}"
}

# Resolved once, and lookups memoized: each is a fork, and screens redraw per
# keypress.
BO_LOCALE=''

declare -A BO_MSG_CACHE=()

BO_MSG_RESULT=''

# bo_msg_into <msgid>
# Lookup into BO_MSG_RESULT, without a fork.
bo_msg_into() {
	local msgid="$1"

	[[ -n $BO_LOCALE ]] || BO_LOCALE="$(bo_ui_locale)"

	if [[ -n ${BO_MSG_CACHE[$msgid]+set} ]]; then
		BO_MSG_RESULT="${BO_MSG_CACHE[$msgid]}"
		return 0
	fi

	BO_MSG_RESULT="$(LC_ALL="$BO_LOCALE" LANGUAGE="${BO_LOCALE%%.*}" gettext -- "$msgid" 2>/dev/null)"
	[[ -n $BO_MSG_RESULT ]] || BO_MSG_RESULT="$msgid"
	BO_MSG_CACHE[$msgid]="$BO_MSG_RESULT"
	return 0
}

# bo_msg <msgid> [printf args...]
bo_msg() {
	local msgid="$1"
	shift

	bo_msg_into "$msgid"

	# Without arguments it is text, not a format: a % would break printf.
	if (( $# == 0 )); then
		printf '%s' "$BO_MSG_RESULT"
		return
	fi

	# shellcheck disable=SC2059  # the format string is the translated message
	printf -- "$BO_MSG_RESULT" "$@"
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# Decided once: inside $(...) stdout is always a pipe.
BO_INTERACTIVE=''
[[ -t 1 ]] && BO_INTERACTIVE=1

if [[ -n $BO_INTERACTIVE && -z ${NO_COLOR:-} ]]; then
	BO_C_RESET=$'\033[0m'
	BO_C_BOLD=$'\033[1m'
	BO_C_DIM=$'\033[2m'
	BO_C_BLUE=$'\033[38;2;23;147;209m'
	BO_C_GREEN=$'\033[32m'
	BO_C_YELLOW=$'\033[33m'
	BO_C_RED=$'\033[31m'
else
	BO_C_RESET='' BO_C_BOLD='' BO_C_DIM='' BO_C_BLUE=''
	BO_C_GREEN='' BO_C_YELLOW='' BO_C_RED=''
fi

# Set by bo_bad and bo_note: the menu waits for a key before redrawing.
BO_UI_NEEDS_ACK=''

# --quiet, for the systemd unit. Errors still go to stderr.
BO_QUIET=''

bo_say()  { [[ -n $BO_QUIET ]] || printf '%s\n' "$*"; }
bo_head() { printf '\n%s%s%s\n\n' "$BO_C_BOLD$BO_C_BLUE" "$*" "$BO_C_RESET"; }
bo_ok()   { [[ -n $BO_QUIET ]] || printf '%s✔%s %s\n' "$BO_C_GREEN" "$BO_C_RESET" "$*"; }
bo_bad()  { BO_UI_NEEDS_ACK=1; printf '%s✘%s %s\n' "$BO_C_RED" "$BO_C_RESET" "$*" >&2; }
bo_note() { BO_UI_NEEDS_ACK=1; [[ -n $BO_QUIET ]] || printf '%s•%s %s\n' "$BO_C_DIM" "$BO_C_RESET" "$*"; }

bo_have() { command -v "$1" > /dev/null 2>&1; }

# "x minutes ago" for a unix timestamp, "never" for none.
bo_time_ago() {
	local ts="$1" now delta

	[[ $ts =~ ^[0-9]+$ ]] || { bo_msg "never"; printf '\n'; return; }

	now="$(date +%s)"
	delta=$(( now - ts ))
	(( delta < 0 )) && delta=0

	if   (( delta < 60 ));     then bo_msg "just now"
	elif (( delta < 120 ));    then bo_msg "1 minute ago"
	elif (( delta < 3600 ));   then bo_msg "%d minutes ago" "$(( delta / 60 ))"
	elif (( delta < 7200 ));   then bo_msg "1 hour ago"
	elif (( delta < 86400 ));  then bo_msg "%d hours ago" "$(( delta / 3600 ))"
	elif (( delta < 172800 )); then bo_msg "1 day ago"
	else                            bo_msg "%d days ago" "$(( delta / 86400 ))"
	fi
	printf '\n'
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

bo_state_read() {
	local key="$1" default="${2:-}"
	if [[ -r "$BO_STATEDIR/$key" ]]; then
		cat "$BO_STATEDIR/$key"
	else
		printf '%s\n' "$default"
	fi
}

bo_state_write() {
	local key="$1"
	shift
	mkdir -p "$BO_STATEDIR" 2>/dev/null || return 1
	printf '%s\n' "$*" > "$BO_STATEDIR/$key"
}

# ---------------------------------------------------------------------------
# The change ledger
# ---------------------------------------------------------------------------
# Every change, so undoing never touches what this did not write. A set, tab
# separated:
#   file     <path>        -            deleted on undo
#   default  <MIME type>   <previous>   put back on undo, "-" for none

bo_ledger_add() {
	local kind="$1" key="$2" detail="${3:--}"
	mkdir -p "$BO_STATEDIR" 2>/dev/null || return 1

	# Keep the value from before the first time.
	if [[ $kind == default ]] && bo_ledger_has default "$key"; then
		return 0
	fi

	bo_ledger_forget "$kind" "$key"
	printf '%s\t%s\t%s\n' "$kind" "$key" "$detail" >> "$BO_LEDGER"
}

# bo_ledger_has <kind> <key>
bo_ledger_has() {
	[[ -f $BO_LEDGER ]] || return 1
	awk -F'\t' -v k="$1" -v p="$2" '$1 == k && $2 == p { found = 1 } END { exit !found }' \
		"$BO_LEDGER"
}

# bo_ledger_detail <kind> <key>
bo_ledger_detail() {
	[[ -f $BO_LEDGER ]] || return 1
	awk -F'\t' -v k="$1" -v p="$2" '$1 == k && $2 == p { d = $3; f = 1 } END { if (!f) exit 1; print d }' \
		"$BO_LEDGER"
}

bo_ledger_forget() {
	local kind="$1" key="$2" tmp
	[[ -f $BO_LEDGER ]] || return 0

	tmp="$(mktemp "${BO_LEDGER}.XXXXXX")" || return 1
	awk -F'\t' -v k="$kind" -v p="$key" '!($1 == k && $2 == p)' "$BO_LEDGER" > "$tmp" 2>/dev/null \
		&& mv -f "$tmp" "$BO_LEDGER" || rm -f "$tmp"
	return 0
}

# bo_ledger_list <kind>
# Every key of that kind, one per line.
bo_ledger_list() {
	[[ -f $BO_LEDGER ]] || return 0
	awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$BO_LEDGER"
}

# bo_write_if_changed <path> <content>
# 0 written, 1 already so, 2 failed. An unchanged file keeps its timestamp, so
# desktops do not rebuild their caches for nothing.
bo_write_if_changed() {
	local path="$1" content="$2" current=''

	# $(...) drops the final newline.
	[[ $content == *$'\n' ]] || content+=$'\n'

	# Byte for byte: $(< file) would drop trailing newlines.
	[[ -r $path ]] && IFS= read -rd '' current < "$path"

	[[ $current == "$content" ]] && return 1

	mkdir -p "$(dirname "$path")" 2>/dev/null || return 2
	printf '%s' "$content" > "$path" || return 2
	return 0
}
