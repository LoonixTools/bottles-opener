# shellcheck shell=bash
#
# Finding Bottles, its bottles and the programs in them.
#
# Native (bottles-cli, ~/.local/share/bottles) and Flatpak (~/.var/app/...),
# possibly both. Everything is tagged with its install: it decides how a
# program is started.

# The installations present, "native" and/or "flatpak". Filled once per run.
BO_INSTALLS=()
BO_INSTALLS_DONE=0

bo_installs_detect() {
	(( BO_INSTALLS_DONE )) && return 0
	BO_INSTALLS_DONE=1
	BO_INSTALLS=()

	# For testing against a fixed set; not documented anywhere else.
	if [[ -n ${BO_FORCE_INSTALLS+set} ]]; then
		read -ra BO_INSTALLS <<< "$BO_FORCE_INSTALLS"
		return 0
	fi

	bo_have bottles-cli && BO_INSTALLS+=(native)
	if bo_have flatpak && flatpak info "$BO_FLATPAK_ID" > /dev/null 2>&1; then
		BO_INSTALLS+=(flatpak)
	fi
	return 0
}

bo_install_present() {
	local i
	bo_installs_detect
	for i in "${BO_INSTALLS[@]}"; do
		[[ $i == "$1" ]] && return 0
	done
	return 1
}

# bo_install_data <install>
# The directory holding bottles/ for that installation.
bo_install_data() {
	case "$1" in
		native)  printf '%s\n' "${BO_NATIVE_DATA:-$BO_XDG_DATA}" ;;
		flatpak) printf '%s\n' "${BO_FLATPAK_DATA:-$HOME/.var/app/$BO_FLATPAK_ID/data}" ;;
	esac
}

# ---------------------------------------------------------------------------
# The scan
# ---------------------------------------------------------------------------

BO_ROOTS=()        # every bottles directory, for the watcher
BO_CONFS=()        # every bottle.yml, for the watcher

BO_B_INSTALL=()    # one entry per bottle
BO_B_NAME=()

BO_P_INSTALL=()    # one entry per program
BO_P_BOTTLE=()
BO_P_BDIR=()
BO_P_ID=()
BO_P_NAME=()
BO_P_PATH=()
BO_P_ICON=()

BO_R_INSTALL=()    # one entry per type a program registered in its bottle
BO_R_PID=()
BO_R_EXT=()
BO_R_ARGS=()
BO_R_ICON=()
BO_R_IDX=()
BO_R_DESC=()
declare -A BO_R_AT=()  # ext \x1f install \x1f program id -> index into BO_R_*
declare -A BO_P_AT=()  # install \x1f program id -> index into BO_P_*

# An install that could not be read, rather than one that is empty.
BO_SCAN_ERROR=''

BO_SCANNED=0

# _bo_scan_run <install> <data home>
# The host's Python first; the Flatpak's, which surely has PyYAML, as fallback.
_bo_scan_run() {
	local install="$1" data="$2" rc=127

	if bo_have python3; then
		python3 "$BO_LIBDIR/scan.py" "$data" "$BO_CACHEDIR/registry"
		rc=$?
	fi

	if (( rc == 3 || rc == 127 )) && [[ $install == flatpak ]]; then
		flatpak run --command=python3 "$BO_FLATPAK_ID" - "$data" \
			< "$BO_LIBDIR/scan.py" 2>/dev/null
		rc=$?
	fi

	return "$rc"
}

bo_scan() {
	local install data kind a b c d e f g out bdir

	BO_ROOTS=(); BO_CONFS=()
	BO_B_INSTALL=(); BO_B_NAME=()
	BO_P_INSTALL=(); BO_P_BOTTLE=(); BO_P_BDIR=(); BO_P_ID=()
	BO_P_NAME=(); BO_P_PATH=(); BO_P_ICON=()
	BO_R_INSTALL=(); BO_R_PID=(); BO_R_EXT=(); BO_R_ARGS=()
	BO_R_ICON=(); BO_R_IDX=(); BO_R_DESC=(); BO_R_AT=(); BO_P_AT=()
	BO_SCAN_ERROR=''

	bo_installs_detect

	for install in "${BO_INSTALLS[@]}"; do
		data="$(bo_install_data "$install")"

		if ! out="$(_bo_scan_run "$install" "$data")"; then
			BO_SCAN_ERROR="$install"
			continue
		fi

		declare -A dirs=()
		while IFS=$'\x1f' read -r kind a b c d e f g; do
			case "$kind" in
				R)
					BO_ROOTS+=("$a")
					;;
				B)
					BO_B_INSTALL+=("$install"); BO_B_NAME+=("$a")
					BO_CONFS+=("$c")
					dirs[$a]="$b"
					;;
				P)
					bdir="${dirs[$a]:-}"
					[[ -n $bdir && -n $b ]] || continue
					BO_P_AT[$install$'\x1f'$b]=${#BO_P_ID[@]}
					BO_P_INSTALL+=("$install"); BO_P_BOTTLE+=("$a")
					BO_P_BDIR+=("$bdir"); BO_P_ID+=("$b")
					BO_P_NAME+=("$c"); BO_P_PATH+=("$d"); BO_P_ICON+=("$e")
					;;
				A)
					BO_R_AT[$c$'\x1f'$install$'\x1f'$b]=${#BO_R_EXT[@]}
					BO_R_INSTALL+=("$install"); BO_R_PID+=("$b"); BO_R_EXT+=("$c")
					BO_R_ARGS+=("$d"); BO_R_ICON+=("$e"); BO_R_IDX+=("$f")
					BO_R_DESC+=("$g")
					;;
			esac
		done <<< "$out"
		unset dirs
	done

	BO_SCANNED=1
	return 0
}

bo_scan_once() {
	(( BO_SCANNED )) || bo_scan
}

# bo_program_find <install> <program id>
# Index into the BO_P_* arrays, in BO_FOUND; returns 1 when there is none.
BO_FOUND=-1

bo_program_find() {
	BO_FOUND="${BO_P_AT[$1$'\x1f'$2]:--1}"
	(( BO_FOUND >= 0 ))
}

# bo_program_label <index>
# "FL Studio · FL Studio", plus "(Flatpak)" when both installs exist.
BO_LABEL=''

bo_program_label() {
	local i="$1"
	BO_LABEL="${BO_P_NAME[i]} · ${BO_P_BOTTLE[i]}"
	if [[ ${BO_P_INSTALL[i]} == flatpak ]] && bo_install_present native; then
		BO_LABEL+=" (Flatpak)"
	fi
}
