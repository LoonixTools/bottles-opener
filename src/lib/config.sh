# shellcheck shell=bash
#
# Reading and writing ~/.config/bottles-opener/config and .../types.
# Written by the interface, never by hand. Parsed, not sourced.

BO_CONFIG_CACHE=''
BO_CONFIG_CACHED=0

_bo_config_slurp() {
	(( BO_CONFIG_CACHED )) && return 0
	BO_CONFIG_CACHE=''
	[[ -r $BO_CONFIG ]] && BO_CONFIG_CACHE="$(< "$BO_CONFIG")"
	BO_CONFIG_CACHED=1
	return 0
}

# _bo_config_lookup <Key> [default]
# Into BO_CONFIG_VALUE, without a fork: the settings screen reads every key per
# frame.
BO_CONFIG_VALUE=''

_bo_config_lookup() {
	local key="$1" default="${2:-}" val='' line

	BO_CONFIG_VALUE="$default"
	[[ -r $BO_CONFIG ]] || return 0
	_bo_config_slurp

	while IFS= read -r line; do
		[[ $line == *"$key"* ]] || continue
		[[ $line =~ ^[[:space:]]*"$key"[[:space:]]*=(.*)$ ]] || continue
		val="${BASH_REMATCH[1]}"
	done <<< "$BO_CONFIG_CACHE"

	val="${val%%#*}"
	val="${val#"${val%%[![:space:]]*}"}"
	val="${val%"${val##*[![:space:]]}"}"
	val="${val%\"}"
	val="${val#\"}"

	[[ -n $val ]] && BO_CONFIG_VALUE="$val"
	return 0
}

# bo_config_get <Key> [default]
bo_config_get() {
	_bo_config_lookup "$@"
	printf '%s\n' "$BO_CONFIG_VALUE"
}

_bo_is_true() {
	case "${1,,}" in
		yes|y|true|1|on|enabled) return 0 ;;
		*) return 1 ;;
	esac
}

# bo_config_bool <Key> <default: yes|no>
bo_config_bool() {
	_bo_config_lookup "$1" "$2"
	_bo_is_true "$BO_CONFIG_VALUE"
}

# bo_config_set <Key> <Value>
bo_config_set() {
	local key="$1" value="$2" tmp

	if [[ ! -e $BO_CONFIG ]]; then
		mkdir -p "$(dirname "$BO_CONFIG")" || return 1
		{
			printf '# %s\n' "$BO_PRETTY"
			printf '#\n'
			printf '# Written by `%s`. Nothing here needs editing by hand -\n' "$BO_NAME"
			printf '# every option is reachable from `%s` itself.\n' "$BO_NAME"
		} > "$BO_CONFIG" || return 1
	fi
	[[ -w $BO_CONFIG ]] || return 1

	tmp="$(mktemp "${BO_CONFIG}.XXXXXX")" || return 1
	chmod --reference="$BO_CONFIG" "$tmp" 2>/dev/null || chmod 0644 "$tmp"

	if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=" "$BO_CONFIG"; then
		awk -v key="$key" -v value="$value" '
			!done && $0 ~ "^[[:space:]]*#?[[:space:]]*" key "[[:space:]]*=" {
				print key "=" value; done = 1; next
			}
			# drop any further occurrences so the file cannot grow duplicates
			$0 ~ "^[[:space:]]*" key "[[:space:]]*=" { next }
			{ print }
		' "$BO_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
	else
		cat "$BO_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
		printf '%s=%s\n' "$key" "$value" >> "$tmp"
	fi

	mv -f "$tmp" "$BO_CONFIG"
	BO_CONFIG_CACHED=0
}

# ---------------------------------------------------------------------------
# Resolved settings
# ---------------------------------------------------------------------------

bo_config_load() {
	CFG_ENABLED=no; bo_config_bool Enabled          no  && CFG_ENABLED=yes
	CFG_DETECT=no;  bo_config_bool DetectKnown      yes && CFG_DETECT=yes
	CFG_ICONS=no;   bo_config_bool FileIcons        yes && CFG_ICONS=yes
	CFG_WATCH=no;   bo_config_bool WatchNewPrograms yes && CFG_WATCH=yes
	bo_types_load
}

# ---------------------------------------------------------------------------
# The types file
# ---------------------------------------------------------------------------
# Types changed by hand. Detected ones have no line: they follow detection.
# Tab separated, no field empty:
#   <extension> <default|openwith|off> <install> <program id> <bottle name>
# The program is found by install and id; the bottle name is for reading.

BO_T_EXT=()
BO_T_STATE=()
BO_T_INSTALL=()
BO_T_PID=()
BO_T_BOTTLE=()

bo_types_load() {
	local ext state install pid bottle

	BO_T_EXT=(); BO_T_STATE=(); BO_T_INSTALL=(); BO_T_PID=(); BO_T_BOTTLE=()
	[[ -r $BO_TYPES ]] || return 0

	while IFS=$'\t' read -r ext state install pid bottle; do
		[[ -z $ext || $ext == '#'* || -z $pid ]] && continue
		case "$state" in default|openwith|off) ;; *) continue ;; esac
		BO_T_EXT+=("$ext"); BO_T_STATE+=("$state"); BO_T_INSTALL+=("$install")
		BO_T_PID+=("$pid"); BO_T_BOTTLE+=("$bottle")
	done < "$BO_TYPES"
}

# bo_types_set <ext> <state|remove> <install> <program id> <bottle name>
# Replaces the line for that extension and program, or takes it out.
bo_types_set() {
	local ext="$1" state="$2" install="$3" pid="$4" bottle="$5" tmp

	mkdir -p "$(dirname "$BO_TYPES")" || return 1
	if [[ ! -e $BO_TYPES ]]; then
		{
			printf '# %s: file types changed by hand\n' "$BO_PRETTY"
			printf '#\n'
			printf '# Written by `%s`. Nothing here needs editing by hand.\n' "$BO_NAME"
		} > "$BO_TYPES" || return 1
	fi

	tmp="$(mktemp "${BO_TYPES}.XXXXXX")" || return 1
	awk -F'\t' -v e="$ext" -v i="$install" -v p="$pid" \
		'!($1 == e && $3 == i && $4 == p)' "$BO_TYPES" > "$tmp" \
		|| { rm -f "$tmp"; return 1; }

	if [[ $state != remove ]]; then
		printf '%s\t%s\t%s\t%s\t%s\n' "$ext" "$state" "$install" "$pid" "$bottle" >> "$tmp"
	fi

	mv -f "$tmp" "$BO_TYPES"
	bo_types_load
}
