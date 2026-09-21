# shellcheck shell=bash
#
# The interactive front end.

# Non-canonical mode for the whole interface: between two `read -sn1` bash
# goes back to canonical mode, where a backspace gets eaten.
BO_TERM_SAVED=''

bo_ui_term_raw() {
	bo_have stty || return 0
	[[ -t 0 ]] || return 0
	[[ -n $BO_TERM_SAVED ]] && return 0

	BO_TERM_SAVED="$(stty -g 2>/dev/null)" || { BO_TERM_SAVED=''; return 0; }
	stty -icanon -echo min 1 time 0 2>/dev/null || true
}

bo_ui_term_restore() {
	[[ -n $BO_TERM_SAVED ]] || return 0
	stty "$BO_TERM_SAVED" 2>/dev/null || true
	BO_TERM_SAVED=''
}

# Runs an action in normal line mode.
bo_ui_cooked() {
	bo_ui_term_restore
	"$@"
	local rc=$?
	bo_ui_term_raw
	return $rc
}

# bo_read_key
# One keypress as a name. Escape sequences are read whole.
bo_read_key() {
	local k rest tail

	IFS= read -rsn1 k || return 1

	case "$k" in
		$'\e')
			if IFS= read -rsn2 -t 0.05 rest; then
				case "$rest" in
					'[A') printf 'up\n' ;;
					'[B') printf 'down\n' ;;
					'[C') printf 'right\n' ;;
					'[D') printf 'left\n' ;;
					'[3')
						IFS= read -rsn1 -t 0.05 tail || true
						printf 'delete\n'
						;;
					*)    printf 'escape\n' ;;
				esac
			else
				printf 'escape\n'
			fi
			;;
		''|$'\r')      printf 'enter\n' ;;
		$'\x7f'|$'\b') printf 'backspace\n' ;;
		' ')           printf 'space\n' ;;
		*)             printf '%s\n' "$k" ;;
	esac
}

# bo_ui_read_line <initial>
# A line editor into BO_LINE_RESULT. `read -r` would break the following
# `read -sn1`.
BO_LINE_RESULT=''

bo_ui_read_line() {
	local buf="${1:-}" key

	BO_LINE_RESULT=''
	printf '%s' "$buf"

	while true; do
		key="$(bo_read_key)" || { printf '\n'; return 1; }

		case "$key" in
			enter)
				printf '\n'
				BO_LINE_RESULT="$buf"
				return 0
				;;
			escape)
				printf '\n'
				return 1
				;;
			backspace)
				if [[ -n $buf ]]; then
					buf="${buf%?}"
					printf '\b \b'
				fi
				;;
			space)
				buf+=' '
				printf ' '
				;;
			up|down|left|right|delete) ;;
			*)
				[[ ${#key} -eq 1 ]] || continue
				buf+="$key"
				printf '%s' "$key"
				;;
		esac
	done
}

bo_pause() {
	printf '\n  %s' "$(bo_msg "Press any key to continue...")"
	read -rsn1 _ || true
	printf '\n'
}

# _bo_row <label> <value>
# Padded by characters: printf pads by bytes, which "ü" gets wrong.
_bo_row() {
	local label="$1" value="$2" pad
	pad=$(( 30 - ${#label} ))
	(( pad < 0 )) && pad=0
	printf '  %s%*s %s\n' "$label" "$pad" '' "$value"
}

_bo_onoff() {
	if [[ $1 == yes ]]; then
		printf '%s%s%s' "$BO_C_GREEN" "$(bo_msg "ON")" "$BO_C_RESET"
	else
		printf '%s%s%s' "$BO_C_DIM" "$(bo_msg "OFF")" "$BO_C_RESET"
	fi
}

BO_CLEARSEQ=''

_bo_clearseq() {
	[[ -n $BO_CLEARSEQ ]] && return 0
	BO_CLEARSEQ="$(clear 2>/dev/null)" || BO_CLEARSEQ=$'\033[H\033[2J'
}

# _bo_term_rows [reserved]
# How many list rows fit, in BO_ROWS.
BO_ROWS=20

_bo_term_rows() {
	local size
	size="$(stty size 2>/dev/null)" || size='24 80'
	BO_ROWS=$(( ${size%% *} - ${1:-8} ))
	(( BO_ROWS < 5 )) && BO_ROWS=5
}

# _bo_scroll <cursor> <top>
# The first row to show so the cursor is in view, in BO_TOP.
BO_TOP=0

_bo_scroll() {
	BO_TOP=$2
	(( $1 < BO_TOP )) && BO_TOP=$1
	(( $1 >= BO_TOP + BO_ROWS )) && BO_TOP=$(( $1 - BO_ROWS + 1 ))
	(( BO_TOP < 0 )) && BO_TOP=0
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

# bo_ui_status
# For `status` and the menu header, from a fresh scan.
bo_ui_status() {
	local last exts nb=0 np install where=''

	bo_assoc_compute
	bo_assoc_counts
	last="$(bo_state_read last_apply '')"

	_bo_row "$(bo_msg "File opening")" "$(_bo_onoff "$CFG_ENABLED")"
	printf '\n'

	for install in "${BO_INSTALLS[@]}"; do
		case "$install" in
			native)  where+="${where:+, }$(bo_msg "package")" ;;
			flatpak) where+="${where:+, }Flatpak" ;;
		esac
	done
	if [[ -z $where ]]; then
		_bo_row "Bottles" "${BO_C_YELLOW}$(bo_msg "not found")${BO_C_RESET}"
	elif [[ -n $BO_SCAN_ERROR ]]; then
		_bo_row "Bottles" \
			"${BO_C_RED}$(bo_msg "could not be read (is python3 with PyYAML installed?)")${BO_C_RESET}"
	else
		_bo_row "Bottles" "$where"
	fi

	nb=${#BO_B_NAME[@]}
	np=${#BO_P_ID[@]}
	if (( nb == 1 )); then
		_bo_row "$(bo_msg "Programs found")" "$(bo_msg "%d in 1 bottle" "$np")"
	else
		_bo_row "$(bo_msg "Programs found")" "$(bo_msg "%d in %d bottles" "$np" "$nb")"
	fi

	exts="$(bo_assoc_active_exts 10)"
	if (( BO_N_ACTIVE )); then
		_bo_row "$(bo_msg "File types")" "$exts"
	else
		_bo_row "$(bo_msg "File types")" "${BO_C_DIM}$(bo_msg "none yet, add one under File types")${BO_C_RESET}"
	fi

	if bo_watch_available; then
		if bo_watch_enabled; then
			_bo_row "$(bo_msg "New programs")" "$(_bo_onoff yes)"
		else
			_bo_row "$(bo_msg "New programs")" "$(_bo_onoff no)"
		fi
	fi

	_bo_row "$(bo_msg "Last applied")" "$(bo_time_ago "$last")"

	if [[ $CFG_ENABLED == yes ]] && (( BO_N_ACTIVE )); then
		printf '\n  %s%s%s\n' "$BO_C_DIM" \
			"$(bo_msg "Double-click one of these files and it opens in its program.")" \
			"$BO_C_RESET"
	fi
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
# Format: Key|default|label-msgid
BO_SETTINGS=(
	"DetectKnown|yes|Find the file types of installed programs"
	"FileIcons|yes|Give files the icon of their program"
	"WatchNewPrograms|yes|Pick up newly installed programs"
)

# bo_ui_settings
# Returns 0 when something changed.
bo_ui_settings() {
	local count=${#BO_SETTINGS[@]}
	local -a names=() defaults=() labels=() values=()
	local spec name default label i key frame row pad dirty=1 cursor=0 touched=0
	local l_on l_off title hint shown

	bo_msg_into "ON";  l_on="$BO_MSG_RESULT"
	bo_msg_into "OFF"; l_off="$BO_MSG_RESULT"

	for spec in "${BO_SETTINGS[@]}"; do
		IFS='|' read -r name default label <<< "$spec"
		names+=("$name"); defaults+=("$default")
		bo_msg_into "$label"
		labels+=("$BO_MSG_RESULT")
	done

	bo_msg_into "Settings"; title="$BO_MSG_RESULT"
	bo_msg_into "Up/Down: select, Space: change, q: back"
	hint="$BO_MSG_RESULT"

	_bo_clearseq

	while true; do
		if (( dirty )); then
			for i in "${!names[@]}"; do
				_bo_config_lookup "${names[i]}" "${defaults[i]}"
				values[i]="$BO_CONFIG_VALUE"
			done
			dirty=0
		fi

		frame="$BO_CLEARSEQ"$'\n'"${BO_C_BOLD}${BO_C_BLUE}  ${title}${BO_C_RESET}"$'\n\n'

		local marker selected="${BO_C_BLUE}▸${BO_C_RESET} "
		for i in "${!names[@]}"; do
			if _bo_is_true "${values[i]}"; then
				shown="${BO_C_GREEN}${l_on}${BO_C_RESET}"
			else
				shown="${BO_C_DIM}${l_off}${BO_C_RESET}"
			fi
			pad=$(( 46 - ${#labels[i]} ))
			(( pad < 0 )) && pad=0
			if (( i == cursor )); then marker="$selected"; else marker='  '; fi
			printf -v row '  %s%s%*s %s' "$marker" "${labels[i]}" "$pad" '' "$shown"
			frame+="$row"$'\n'
		done

		frame+=$'\n'"  ${BO_C_DIM}${hint}${BO_C_RESET}"$'\n'
		printf '%s' "$frame"

		key="$(bo_read_key)" || return "$(( ! touched ))"

		case "$key" in
			up|k)   cursor=$(( (cursor - 1 + count) % count )) ;;
			down|j) cursor=$(( (cursor + 1) % count )) ;;
			space|enter|right|l|left|h)
				if _bo_is_true "${values[cursor]}"; then
					bo_config_set "${names[cursor]}" no
				else
					bo_config_set "${names[cursor]}" yes
				fi || { bo_bad "$(bo_msg "Could not save the setting.")"; bo_pause; }
				touched=1
				dirty=1
				;;
			q|Q|escape) return "$(( ! touched ))" ;;
			*) ;;
		esac
	done
}

# ---------------------------------------------------------------------------
# Picking a program
# ---------------------------------------------------------------------------

# bo_ui_pick_program <title>
# The chosen program's index in BO_PICKED; 1 for none.
BO_PICKED=-1

bo_ui_pick_program() {
	local title="$1" count=${#BO_P_ID[@]} cursor=0 i key frame row hint
	local -a labels=()

	BO_PICKED=-1
	if (( count == 0 )); then
		printf '\n  %s\n' "$(bo_msg "No programs found in any bottle.")"
		bo_pause
		return 1
	fi

	for i in "${!BO_P_ID[@]}"; do
		bo_program_label "$i"
		labels+=("$BO_LABEL")
	done

	bo_msg_into "Up/Down: select, Enter: pick, q: cancel"
	hint="$BO_MSG_RESULT"
	_bo_clearseq
	_bo_term_rows 7
	local top=0

	while true; do
		_bo_scroll "$cursor" "$top"; top=$BO_TOP
		frame="$BO_CLEARSEQ"$'\n'"${BO_C_BOLD}${BO_C_BLUE}  ${title}${BO_C_RESET}"$'\n\n'
		for i in "${!labels[@]}"; do
			(( i < top || i >= top + BO_ROWS )) && continue
			if (( i == cursor )); then
				printf -v row '  %s %s' "${BO_C_BLUE}▸${BO_C_RESET}" "${labels[i]}"
			else
				printf -v row '    %s' "${labels[i]}"
			fi
			frame+="$row"$'\n'
		done
		frame+=$'\n'"  ${BO_C_DIM}${hint}${BO_C_RESET}"$'\n'
		printf '%s' "$frame"

		key="$(bo_read_key)" || return 1
		case "$key" in
			up|k)   cursor=$(( (cursor - 1 + count) % count )) ;;
			down|j) cursor=$(( (cursor + 1) % count )) ;;
			enter|space|right|l)
				BO_PICKED=$cursor
				return 0
				;;
			q|Q|escape|left|h) return 1 ;;
			*) ;;
		esac
	done
}

# _bo_parse_exts <text>
# "flp, .FST *.fsc" -> BO_EXTS=(flp fst fsc). 1 with the bad one in BO_EXT.
BO_EXTS=()

_bo_parse_exts() {
	local word
	BO_EXTS=()
	for word in ${1//,/ }; do
		bo_ext_normalize "$word" || return 1
		[[ " ${BO_EXTS[*]} " == *" $BO_EXT "* ]] || BO_EXTS+=("$BO_EXT")
	done
}

# bo_ui_add_type
# Extensions, then the program. 0 when something was added.
bo_ui_add_type() {
	local ext

	printf '\n  %s\n' "$(bo_msg "Which file extensions? For example: flp fst")"
	printf '  > '
	bo_ui_read_line '' || return 1
	[[ -n ${BO_LINE_RESULT// /} ]] || return 1

	if ! _bo_parse_exts "$BO_LINE_RESULT"; then
		bo_bad "$(bo_msg "\"%s\" is not a file extension." "$BO_EXT")"
		bo_pause
		return 1
	fi

	bo_ui_pick_program "$(bo_msg "Which program opens %s?" ".${BO_EXTS[*]}")" || return 1
	bo_assoc_compute
	for ext in "${BO_EXTS[@]}"; do
		bo_assoc_add "$ext" "$BO_PICKED" || {
			bo_bad "$(bo_msg "Could not save the setting.")"
			bo_pause
			return 1
		}
	done
	return 0
}

# ---------------------------------------------------------------------------
# Programs
# ---------------------------------------------------------------------------

# bo_ui_programs
# Programs and their types; Enter edits the list, custom extensions included.
# 0 when something changed.
bo_ui_programs() {
	local key frame row pad i count cursor=0 top=0 dirty=1 touched=0 exts current
	local title hint empty
	local -a labels=() pexts=()

	bo_msg_into "Programs"; title="$BO_MSG_RESULT"
	bo_msg_into "Up/Down: select, Enter: edit file types, q: back"
	hint="$BO_MSG_RESULT"
	bo_msg_into "No programs found in any bottle."; empty="$BO_MSG_RESULT"

	_bo_clearseq
	printf '%s\n  %s\n' "$BO_CLEARSEQ" "$(bo_msg "Looking at the bottles...")"
	bo_config_load
	bo_scan_once
	count=${#BO_P_ID[@]}
	for i in "${!BO_P_ID[@]}"; do
		bo_program_label "$i"
		labels+=("$BO_LABEL")
	done
	_bo_term_rows 7

	while true; do
		if (( dirty )); then
			bo_config_load
			bo_assoc_compute
			pexts=()
			for i in "${!labels[@]}"; do
				pexts[i]="$(bo_program_exts "$i" 6)"
			done
			dirty=0
		fi

		frame="$BO_CLEARSEQ"$'\n'"${BO_C_BOLD}${BO_C_BLUE}  ${title}${BO_C_RESET}"$'\n\n'
		(( count == 0 )) && frame+="  ${BO_C_DIM}${empty}${BO_C_RESET}"$'\n'

		_bo_scroll "$cursor" "$top"; top=$BO_TOP
		local marker selected="${BO_C_BLUE}▸${BO_C_RESET} "
		for i in "${!labels[@]}"; do
			(( i < top || i >= top + BO_ROWS )) && continue
			exts="${pexts[i]}"
			[[ -n $exts ]] || exts="${BO_C_DIM}-${BO_C_RESET}"
			pad=$(( 40 - ${#labels[i]} ))
			(( pad < 0 )) && pad=0
			if (( i == cursor )); then marker="$selected"; else marker='  '; fi
			printf -v row '  %s%s%*s %s' "$marker" "${labels[i]}" "$pad" '' "$exts"
			frame+="$row"$'\n'
		done

		frame+=$'\n'"  ${BO_C_DIM}${hint}${BO_C_RESET}"$'\n'
		printf '%s' "$frame"

		key="$(bo_read_key)" || return "$(( ! touched ))"

		case "$key" in
			up|k)   (( count )) && cursor=$(( (cursor - 1 + count) % count )) ;;
			down|j) (( count )) && cursor=$(( (cursor + 1) % count )) ;;
			enter|space|right|l)
				(( count )) || continue
				current="$(bo_program_exts "$cursor")"
				current="${current//./}"
				printf '\n  %s\n' "$(bo_msg "File types for %s, separated by spaces:" "${BO_P_NAME[cursor]}")"
				printf '  > '
				bo_ui_read_line "$current" || continue
				if ! _bo_parse_exts "$BO_LINE_RESULT"; then
					bo_bad "$(bo_msg "\"%s\" is not a file extension." "$BO_EXT")"
					bo_pause
					continue
				fi
				bo_program_set_exts "$cursor" "${BO_EXTS[@]}" \
					|| { bo_bad "$(bo_msg "Could not save the setting.")"; bo_pause; }
				touched=1
				dirty=1
				;;
			q|Q|escape|left|h) return "$(( ! touched ))" ;;
			*) ;;
		esac
	done
}

# ---------------------------------------------------------------------------
# File types
# ---------------------------------------------------------------------------

# bo_ui_types
# 0 when something changed.
bo_ui_types() {
	local key frame row pad i k count cursor=0 dirty=1 touched=0 label shown
	local title hint legend warn empty
	local l_default l_openwith l_off l_missing l_added

	bo_msg_into "File types"; title="$BO_MSG_RESULT"
	bo_msg_into "Up/Down: select, Space: switch, a: add, Del: remove, q: back"
	hint="$BO_MSG_RESULT"
	bo_msg_into "\"double-click\" opens it; \"Open With\" only lists the program there."
	legend="$BO_MSG_RESULT"
	bo_msg_into "File opening is off. This is what it would do."
	warn="$BO_MSG_RESULT"
	bo_msg_into "No file types yet. Press a to add one."
	empty="$BO_MSG_RESULT"

	# Resolved once: in the loop, a fork per row per keypress.
	bo_msg_into "double-click";      l_default="$BO_MSG_RESULT"
	bo_msg_into "Open With";         l_openwith="$BO_MSG_RESULT"
	bo_msg_into "off";               l_off="$BO_MSG_RESULT"
	bo_msg_into "program not found"; l_missing="$BO_MSG_RESULT"
	bo_msg_into "added";             l_added="$BO_MSG_RESULT"

	local s_default="${BO_C_GREEN}${l_default}${BO_C_RESET}"
	local s_openwith="${BO_C_GREEN}${l_openwith}${BO_C_RESET}"
	local s_off="${BO_C_DIM}${l_off}${BO_C_RESET}"
	local s_missing="${BO_C_YELLOW}${l_missing}${BO_C_RESET}"

	_bo_clearseq
	printf '%s\n  %s\n' "$BO_CLEARSEQ" "$(bo_msg "Looking at the bottles...")"
	bo_config_load
	bo_scan_once
	_bo_term_rows 11
	local top=0

	while true; do
		if (( dirty )); then
			bo_config_load
			bo_assoc_compute
			count=${#BO_A_ORDER[@]}
			(( cursor >= count )) && cursor=$(( count > 0 ? count - 1 : 0 ))
			dirty=0
		fi

		frame="$BO_CLEARSEQ"$'\n'"${BO_C_BOLD}${BO_C_BLUE}  ${title}${BO_C_RESET}"$'\n\n'

		if (( count == 0 )); then
			frame+="  ${BO_C_DIM}${empty}${BO_C_RESET}"$'\n'
		fi

		_bo_scroll "$cursor" "$top"; top=$BO_TOP
		(( top > 0 )) && frame+="  ${BO_C_DIM}  ↑${BO_C_RESET}"$'\n'

		local marker selected="${BO_C_BLUE}▸${BO_C_RESET} " n=-1
		for k in "${BO_A_ORDER[@]}"; do
			n=$(( n + 1 ))
			(( n < top || n >= top + BO_ROWS )) && continue
			i="${BO_A_PIDX[k]}"
			if (( i >= 0 )); then
				bo_program_label "$i"
				label="$BO_LABEL"
			else
				label="${BO_A_BOTTLE[k]}"
			fi

			if (( i < 0 )); then
				shown="$s_missing"
			else
				case "${BO_A_STATE[k]}" in
					default)  shown="$s_default" ;;
					openwith) shown="$s_openwith" ;;
					*)        shown="$s_off" ;;
				esac
			fi
			[[ ${BO_A_SRC[k]} == added ]] && shown+=" ${BO_C_DIM}(${l_added})${BO_C_RESET}"

			printf -v row '%-9s %s' ".${BO_A_EXT[k]}" "$label"
			pad=$(( 46 - ${#row} ))
			(( pad < 0 )) && pad=0
			if (( n == cursor )); then marker="$selected"; else marker='  '; fi
			printf -v row '  %s%s%*s %s' "$marker" "$row" "$pad" '' "$shown"
			frame+="$row"$'\n'
		done
		(( top + BO_ROWS < count )) && frame+="  ${BO_C_DIM}  ↓${BO_C_RESET}"$'\n'

		frame+=$'\n'
		# Otherwise it reads as what is on.
		if [[ $CFG_ENABLED != yes ]]; then
			frame+="  ${BO_C_YELLOW}${warn}${BO_C_RESET}"$'\n'
		fi
		frame+="  ${BO_C_DIM}${legend}${BO_C_RESET}"$'\n'
		frame+="  ${BO_C_DIM}${hint}${BO_C_RESET}"$'\n'
		printf '%s' "$frame"

		key="$(bo_read_key)" || return "$(( ! touched ))"
		k="${BO_A_ORDER[cursor]:-}"

		case "$key" in
			up|k)   (( count )) && cursor=$(( (cursor - 1 + count) % count )) ;;
			down|j) (( count )) && cursor=$(( (cursor + 1) % count )) ;;
			space|enter|right|l|left|h)
				[[ -n $k ]] || continue
				(( BO_A_PIDX[k] >= 0 )) || continue
				case "${BO_A_STATE[k]}" in
					default)  bo_assoc_set "$k" openwith ;;
					openwith) bo_assoc_set "$k" off ;;
					*)        bo_assoc_set "$k" default ;;
				esac || { bo_bad "$(bo_msg "Could not save the setting.")"; bo_pause; }
				touched=1
				dirty=1
				;;
			a|A|+)
				bo_ui_add_type && touched=1
				dirty=1
				;;
			delete|backspace|d|D|x|-)
				[[ -n $k ]] || continue
				bo_assoc_remove "$k" || { bo_bad "$(bo_msg "Could not save the setting.")"; bo_pause; }
				touched=1
				dirty=1
				;;
			q|Q|escape) return "$(( ! touched ))" ;;
			*) ;;
		esac
	done
}

# ---------------------------------------------------------------------------
# The menu
# ---------------------------------------------------------------------------

bo_ui_menu() {
	local choice

	bo_ui_term_raw
	trap 'bo_ui_term_restore' EXIT INT TERM

	while true; do
		bo_config_load
		# Scan again on every visit.
		BO_SCANNED=0

		clear 2>/dev/null || true
		bo_head "  $BO_PRETTY"
		bo_ui_status
		printf '\n'
		printf '  [1] %s\n' "$(bo_msg "Turn file opening on or off")"
		printf '  [2] %s\n' "$(bo_msg "Re-apply everything")"
		printf '  [3] %s\n' "$(bo_msg "File types")"
		printf '  [4] %s\n' "$(bo_msg "Programs")"
		printf '  [5] %s\n' "$(bo_msg "Settings")"
		printf '  [q] %s\n' "$(bo_msg "Quit")"
		printf '\n  > '

		choice="$(bo_read_key)" || {
			printf '\n'; bo_ui_term_restore; trap - EXIT INT TERM; return 0
		}
		case "$choice" in
			enter|space|up|down|left|right|escape|delete|backspace) choice='' ;;
		esac
		printf '%s\n' "$choice"

		case "$choice" in
			1)
				BO_UI_NEEDS_ACK=''
				if [[ $CFG_ENABLED == yes ]]; then
					bo_ui_cooked bo_do_disable
				else
					bo_ui_cooked bo_do_enable
				fi
				[[ -n $BO_UI_NEEDS_ACK ]] && bo_pause
				;;
			# The repair: everything taken back and written again.
			2)
				bo_ui_cooked bo_do_apply --rebuild
				bo_pause
				;;
			# Quietly: the front screen shows the result. Problems wait.
			3)
				BO_UI_NEEDS_ACK=''
				if bo_ui_types && [[ $CFG_ENABLED == yes ]]; then
					bo_ui_cooked bo_do_apply --quiet
					BO_QUIET=''
				fi
				[[ -n $BO_UI_NEEDS_ACK ]] && bo_pause
				;;
			4)
				BO_UI_NEEDS_ACK=''
				if bo_ui_programs && [[ $CFG_ENABLED == yes ]]; then
					bo_ui_cooked bo_do_apply --quiet
					BO_QUIET=''
				fi
				[[ -n $BO_UI_NEEDS_ACK ]] && bo_pause
				;;
			5)
				BO_UI_NEEDS_ACK=''
				if bo_ui_settings && [[ $CFG_ENABLED == yes ]]; then
					bo_ui_cooked bo_do_apply --quiet
					BO_QUIET=''
				fi
				[[ -n $BO_UI_NEEDS_ACK ]] && bo_pause
				;;
			q|Q) bo_ui_term_restore; trap - EXIT INT TERM; return 0 ;;
			# Redraw. Not Escape: a mistyped arrow key must not quit.
			*) ;;
		esac
	done
}
