# shellcheck shell=bash
#
# Which program opens which file type.
#
# Three sources, later ones winning: what each program registered in its
# bottle's registry, the table in known.sh, and what was set by hand in the
# types file.
#
# States:
#   default   opens on a double click
#   openwith  only offered under "Open With"
#   off       left alone
#
# Used by bo_apply to write everything and by the screens to show it, so what
# they show is what happens.

BO_A_EXT=()       # extension, without the dot
BO_A_STATE=()     # default | openwith | off
BO_A_PIDX=()      # index into BO_P_*, -1 for a program that is gone
BO_A_SRC=()       # detected | added
BO_A_INSTALL=()
BO_A_PID=()
BO_A_BOTTLE=()
BO_A_ARGS=()      # Windows argument template, empty for plain "%1"
BO_A_ICON=()      # file holding the type's Windows icon, empty for none
BO_A_IDX=()       # its DefaultIcon index
BO_A_DESC=()      # the type's name in Windows, empty for none

BO_A_ORDER=()     # indices into BO_A_*, sorted by extension then program

# _bo_assoc_push <ext> <state> <program index> <source> <install> <id> <bottle>
_bo_assoc_push() {
	local r="${BO_R_AT[$1$'\x1f'$5$'\x1f'$6]:-}"

	BO_A_EXT+=("$1"); BO_A_STATE+=("$2"); BO_A_PIDX+=("$3"); BO_A_SRC+=("$4")
	BO_A_INSTALL+=("$5"); BO_A_PID+=("$6"); BO_A_BOTTLE+=("$7")

	if [[ -n $r ]]; then
		BO_A_ARGS+=("${BO_R_ARGS[r]}"); BO_A_ICON+=("${BO_R_ICON[r]}")
		BO_A_IDX+=("${BO_R_IDX[r]}"); BO_A_DESC+=("${BO_R_DESC[r]}")
	else
		BO_A_ARGS+=("${BO_KNOWN_ARGS[$1]:-}"); BO_A_ICON+=(''); BO_A_IDX+=(0); BO_A_DESC+=('')
	fi
}

bo_assoc_compute() {
	local i j k r ext key
	declare -A at=() has_default=()

	BO_A_EXT=(); BO_A_STATE=(); BO_A_PIDX=(); BO_A_SRC=()
	BO_A_INSTALL=(); BO_A_PID=(); BO_A_BOTTLE=()
	BO_A_ARGS=(); BO_A_ICON=(); BO_A_IDX=(); BO_A_DESC=(); BO_A_ORDER=()

	bo_scan_once

	# Detected: registered in the bottle, or known from the table. "auto" is
	# settled below, once every default set by hand is known.
	if [[ $CFG_DETECT == yes ]]; then
		for r in "${!BO_R_EXT[@]}"; do
			bo_program_find "${BO_R_INSTALL[r]}" "${BO_R_PID[r]}" || continue
			i=$BO_FOUND
			key="${BO_R_EXT[r]}"$'\x1f'"${BO_R_INSTALL[r]}"$'\x1f'"${BO_R_PID[r]}"
			[[ -n ${at[$key]+set} ]] && continue
			at[$key]=${#BO_A_EXT[@]}
			BO_KNOWN_ARGS=()
			_bo_assoc_push "${BO_R_EXT[r]}" auto "$i" detected \
				"${BO_R_INSTALL[r]}" "${BO_R_PID[r]}" "${BO_P_BOTTLE[i]}"
		done

		for i in "${!BO_P_ID[@]}"; do
			bo_known_exts "${BO_P_PATH[i]}" || continue
			for ext in $BO_KNOWN; do
				key="$ext"$'\x1f'"${BO_P_INSTALL[i]}"$'\x1f'"${BO_P_ID[i]}"
				[[ -n ${at[$key]+set} ]] && continue
				at[$key]=${#BO_A_EXT[@]}
				_bo_assoc_push "$ext" auto "$i" detected \
					"${BO_P_INSTALL[i]}" "${BO_P_ID[i]}" "${BO_P_BOTTLE[i]}"
			done
		done
	fi

	# Set by hand.
	for j in "${!BO_T_EXT[@]}"; do
		key="${BO_T_EXT[j]}"$'\x1f'"${BO_T_INSTALL[j]}"$'\x1f'"${BO_T_PID[j]}"
		if [[ -n ${at[$key]+set} ]]; then
			BO_A_STATE[at[$key]]="${BO_T_STATE[j]}"
			continue
		fi

		i=-1
		bo_program_find "${BO_T_INSTALL[j]}" "${BO_T_PID[j]}" && i=$BO_FOUND

		# Switched off for a program nothing detects any more: nothing to say.
		[[ $i -lt 0 && ${BO_T_STATE[j]} == off ]] && continue

		at[$key]=${#BO_A_EXT[@]}
		BO_KNOWN_ARGS=()
		(( i >= 0 )) && bo_known_exts "${BO_P_PATH[i]}"
		_bo_assoc_push "${BO_T_EXT[j]}" "${BO_T_STATE[j]}" "$i" added \
			"${BO_T_INSTALL[j]}" "${BO_T_PID[j]}" "${BO_T_BOTTLE[j]}"
	done

	# One default per extension: the first one set by hand.
	for k in "${!BO_A_EXT[@]}"; do
		[[ ${BO_A_STATE[k]} == default && ${BO_A_PIDX[k]} -ge 0 ]] || continue
		ext="${BO_A_EXT[k]}"
		if [[ -n ${has_default[$ext]+set} ]]; then
			BO_A_STATE[k]=openwith
		else
			has_default[$ext]=1
		fi
	done

	# A detected type is the default when this program teaches the system the
	# type, because nothing else could open it. A type the system knows already
	# belongs to an app somebody chose, so it only gets "Open With".
	for k in "${!BO_A_EXT[@]}"; do
		[[ ${BO_A_STATE[k]} == auto ]] || continue
		ext="${BO_A_EXT[k]}"
		bo_mime_for "$ext"
		if (( BO_MIME_OWN )) && [[ -z ${has_default[$ext]+set} ]]; then
			BO_A_STATE[k]=default
			has_default[$ext]=1
		else
			BO_A_STATE[k]=openwith
		fi
	done

	# Sorted for display.
	if (( ${#BO_A_EXT[@]} )); then
		local label
		while IFS=$'\x1f' read -r _ _ k; do
			BO_A_ORDER+=("$k")
		done < <(
			for k in "${!BO_A_EXT[@]}"; do
				if (( BO_A_PIDX[k] >= 0 )); then
					label="${BO_P_NAME[BO_A_PIDX[k]]}"
				else
					label="~"
				fi
				printf '%s\x1f%s\x1f%s\n' "${BO_A_EXT[k]}" "${label,,}" "$k"
			done | LC_ALL=C sort -t $'\x1f' -k1,1 -k2,2
		)
	fi
}

# bo_assoc_counts
# BO_N_ACTIVE: types that are on, with their program present.
BO_N_ACTIVE=0

bo_assoc_counts() {
	local k
	BO_N_ACTIVE=0
	for k in "${!BO_A_EXT[@]}"; do
		[[ ${BO_A_STATE[k]} != off && ${BO_A_PIDX[k]} -ge 0 ]] \
			&& BO_N_ACTIVE=$(( BO_N_ACTIVE + 1 ))
	done
}

# bo_assoc_active_exts [max]
# The extensions that are on, sorted, deduplicated. With a maximum, the rest
# is counted: ".flp .fst .doc +12".
bo_assoc_active_exts() {
	local max="${1:-0}" k n=0 out=''
	declare -A seen=()
	for k in "${BO_A_ORDER[@]}"; do
		[[ ${BO_A_STATE[k]} != off && ${BO_A_PIDX[k]} -ge 0 ]] || continue
		[[ -n ${seen[${BO_A_EXT[k]}]+set} ]] && continue
		seen[${BO_A_EXT[k]}]=1
		n=$(( n + 1 ))
		(( max > 0 && n > max )) && continue
		out+="${out:+ }.${BO_A_EXT[k]}"
	done
	(( max > 0 && n > max )) && out+=" +$(( n - max ))"
	printf '%s\n' "$out"
}

# bo_program_exts <program index> [max]
# The extensions that are on for one program, like bo_assoc_active_exts.
bo_program_exts() {
	local i="$1" max="${2:-0}" k n=0 out=''
	for k in "${BO_A_ORDER[@]}"; do
		[[ ${BO_A_PIDX[k]} == "$i" && ${BO_A_STATE[k]} != off ]] || continue
		n=$(( n + 1 ))
		(( max > 0 && n > max )) && continue
		out+="${out:+ }.${BO_A_EXT[k]}"
	done
	(( max > 0 && n > max )) && out+=" +$(( n - max ))"
	printf '%s\n' "$out"
}

# _bo_assoc_demote <extension> <install> <program id>
# Every other program that is the default for the extension becomes an
# "Open With" entry.
_bo_assoc_demote() {
	local ext="$1" install="$2" pid="$3" o

	for o in "${!BO_A_EXT[@]}"; do
		[[ ${BO_A_EXT[o]} == "$ext" && ${BO_A_STATE[o]} == default ]] || continue
		[[ ${BO_A_INSTALL[o]} == "$install" && ${BO_A_PID[o]} == "$pid" ]] && continue
		bo_types_set "$ext" openwith "${BO_A_INSTALL[o]}" \
			"${BO_A_PID[o]}" "${BO_A_BOTTLE[o]}" || return 1
	done
}

# bo_assoc_set <index into BO_A_*> <state>
bo_assoc_set() {
	local k="$1" state="$2"

	if [[ $state == default ]]; then
		_bo_assoc_demote "${BO_A_EXT[k]}" "${BO_A_INSTALL[k]}" "${BO_A_PID[k]}" || return 1
	fi

	bo_types_set "${BO_A_EXT[k]}" "$state" "${BO_A_INSTALL[k]}" \
		"${BO_A_PID[k]}" "${BO_A_BOTTLE[k]}" || return 1

	[[ $state == default ]] && bo_default_claim "${BO_A_EXT[k]}"
	return 0
}

# bo_assoc_remove <index into BO_A_*>
# Added by hand: gone. Detected: switched off, or detection brings it back.
bo_assoc_remove() {
	local k="$1" how=remove
	[[ ${BO_A_SRC[k]} == detected ]] && how=off
	bo_types_set "${BO_A_EXT[k]}" "$how" "${BO_A_INSTALL[k]}" \
		"${BO_A_PID[k]}" "${BO_A_BOTTLE[k]}"
}

# bo_assoc_add <extension> <index into BO_P_*> [state]
# Without a state: the default for a type only this program can open, unless
# another program is already; "Open With" for one the system knows.
bo_assoc_add() {
	local ext="$1" i="$2" state="${3:-}" k

	if [[ -z $state ]]; then
		bo_mime_for "$ext"
		state=default
		(( BO_MIME_OWN )) || state=openwith
		for k in "${!BO_A_EXT[@]}"; do
			if [[ ${BO_A_EXT[k]} == "$ext" && ${BO_A_STATE[k]} == default \
				&& ${BO_A_PIDX[k]} -ge 0 && ${BO_A_PIDX[k]} -ne $i ]]; then
				state=openwith
				break
			fi
		done
	fi

	if [[ $state == default ]]; then
		_bo_assoc_demote "$ext" "${BO_P_INSTALL[i]}" "${BO_P_ID[i]}" || return 1
	fi

	bo_types_set "$ext" "$state" "${BO_P_INSTALL[i]}" "${BO_P_ID[i]}" "${BO_P_BOTTLE[i]}" \
		|| return 1

	[[ $state == default ]] && bo_default_claim "$ext"
	return 0
}

# bo_program_set_exts <program index> <extension>...
# Makes exactly these the types the program opens: new ones are added, ones
# left out are removed. Returns 1 when something could not be saved.
bo_program_set_exts() {
	local i="$1" k ext
	shift
	local want=" $* "

	for k in "${BO_A_ORDER[@]}"; do
		[[ ${BO_A_PIDX[k]} == "$i" && ${BO_A_STATE[k]} != off ]] || continue
		[[ $want == *" ${BO_A_EXT[k]} "* ]] && continue
		bo_assoc_remove "$k" || return 1
	done

	for ext in "$@"; do
		for k in "${BO_A_ORDER[@]}"; do
			[[ ${BO_A_PIDX[k]} == "$i" && ${BO_A_EXT[k]} == "$ext" && ${BO_A_STATE[k]} != off ]] \
				&& continue 2
		done
		bo_assoc_add "$ext" "$i" || return 1
	done
}
