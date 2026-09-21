# shellcheck shell=bash
#
# Opening a file: what a launcher runs on a double click.
#
# The file is handed over as Explorer would: a Windows path (C:\ inside the
# bottle, Z:\ for the rest), since "/home/..." reads like a switch to many
# programs. The Flatpak gets it through the document portal first.

# bo_uri_to_path <argument>
# file:// URI to path, in BO_PATH. Returns 1 for anything not local.
BO_PATH=''

bo_uri_to_path() {
	local s="$1"

	case "$s" in
		file://*)
			s="${s#file://}"
			# localhost is local; other hosts are not.
			if [[ $s == localhost/* ]]; then
				s="/${s#localhost/}"
			elif [[ $s != /* ]]; then
				BO_PATH="$1"
				return 1
			fi
			# Percent-decoding; backslashes doubled for printf %b.
			s="${s//\\/\\\\}"
			s="${s//%/\\x}"
			printf -v s '%b' "$s"
			;;
	esac

	BO_PATH="$s"
}

# bo_winpath <bottle directory> <absolute path>
# The path through the drive with the longest matching target, in BO_WINPATH.
BO_WINPATH=''

bo_winpath() {
	local bdir="$1" path="$2" dev target letter best='' best_target='' best_len=-1 len rest

	BO_WINPATH=''

	for dev in "$bdir"/dosdevices/?:; do
		[[ -e $dev ]] || continue
		target="$(readlink -f -- "$dev")" || continue

		if [[ $target == / ]]; then
			len=0
		elif [[ $path == "$target" || $path == "$target"/* ]]; then
			len=${#target}
		else
			continue
		fi

		if (( len > best_len )); then
			best_len=$len
			best="$dev"
			best_target="$target"
		fi
	done

	[[ -n $best ]] || return 1

	letter="${best##*/}"
	letter="${letter%:}"

	if [[ $best_target == / ]]; then
		rest="$path"
	else
		rest="${path#"$best_target"}"
	fi
	rest="${rest//\//\\}"
	[[ $rest == \\* ]] || rest="\\$rest"

	BO_WINPATH="${letter^^}:$rest"
}

# bo_open_fail <message>
# On the terminal, or as a notification when started from a file manager.
bo_open_fail() {
	printf '%s: %s\n' "$BO_NAME" "$1" >&2
	if [[ ! -t 2 ]] && bo_have notify-send; then
		notify-send --app-name="$BO_PRETTY" --icon=dialog-error \
			"$BO_PRETTY" "$1" > /dev/null 2>&1 || true
	fi
	return 1
}

# bo_cli_has_program_id <install>
# Whether bottles-cli knows --program-id (older ones only names). Read, not
# run: running it costs a second and a half per double click.
bo_cli_has_program_id() {
	local cli loc

	case "$1" in
		native)
			cli="$(command -v bottles-cli)" || return 1
			;;
		flatpak)
			loc="$(flatpak info --show-location "$BO_FLATPAK_ID" 2>/dev/null)" || return 1
			cli="$loc/files/bin/bottles-cli"
			;;
	esac

	[[ -r $cli ]] && grep -q -- '--program-id' "$cli" 2>/dev/null
}

# _bo_win_args <template> <windows path>
# The arguments Windows would pass, in BO_WARGS: the registry's template with
# the file for %1. Office's /o "%u" and other placeholders are dropped. A
# template without %1 relies on DDE (Excel's /dde): then only the file.
BO_WARGS=()

_bo_win_args() {
	local t="$1" file="$2" c j cur='' have=0 quoted=0 placed=0 tok last
	local -a toks=()

	for (( j = 0; j < ${#t}; j++ )); do
		c="${t:j:1}"
		if [[ $c == '"' ]]; then
			quoted=$(( ! quoted )); have=1
		elif [[ $c == [[:space:]] ]] && (( ! quoted )); then
			(( have )) && toks+=("$cur")
			cur=''; have=0
		else
			cur+="$c"; have=1
		fi
	done
	(( have )) && toks+=("$cur")

	BO_WARGS=()
	for tok in "${toks[@]}"; do
		if [[ $tok == *%[1lLvV]* ]]; then
			tok="${tok//%1/"$file"}"; tok="${tok//%[lL]/"$file"}"; tok="${tok//%[vV]/"$file"}"
			BO_WARGS+=("$tok")
			placed=1
		elif [[ $tok == *%[uU]* ]]; then
			# ...and the switch in front of it.
			last=$(( ${#BO_WARGS[@]} - 1 ))
			if (( last >= 0 )) && [[ ${BO_WARGS[last]} == [/-]* && ${BO_WARGS[last]} != *%* ]]; then
				unset "BO_WARGS[last]"
				BO_WARGS=("${BO_WARGS[@]}")
			fi
		elif [[ $tok == *%[*0-9A-Za-z~]* ]]; then
			continue
		else
			BO_WARGS+=("$tok")
		fi
	done

	(( placed )) || BO_WARGS=("$file")
}

# bo_do_open <launcher id> [file...]
bo_do_open() {
	local id="${1:-}" line install pid bottle bdir pname arg path ext template
	local -a winargs=() cmd=()
	shift || true

	if [[ ! $id =~ ^[0-9a-f]{12}$ ]]; then
		bo_open_fail "$(bo_msg "Usage: bottles-opener open <launcher> [file...]")"
		return 1
	fi

	line="$(awk -F'\t' -v id="$id" '$1 == id { print; exit }' "$BO_LAUNCHERS" 2>/dev/null)"
	if [[ -z $line ]]; then
		bo_open_fail "$(bo_msg "This launcher is out of date. Run \"bottles-opener apply\" and try again.")"
		return 1
	fi
	IFS=$'\t' read -r _ install pid bottle bdir pname <<< "$line"

	for arg in "$@"; do
		# Not a local file: passed as it is.
		if ! bo_uri_to_path "$arg"; then
			winargs+=("$arg")
			continue
		fi
		path="$BO_PATH"
		[[ $path == /* ]] || path="$PWD/$path"

		if [[ ! -e $path ]]; then
			bo_open_fail "$(bo_msg "The file %s does not exist." "$path")"
			return 1
		fi
		path="$(readlink -f -- "$path")"

		if [[ $install == flatpak && $path != "$bdir"/* ]]; then
			# Writable, so the program can save it.
			if ! path="$(flatpak document-export --app="$BO_FLATPAK_ID" \
					--allow-read --allow-write -- "$path" 2>/dev/null)" || [[ -z $path ]]; then
				bo_open_fail "$(bo_msg "Could not hand %s to the Bottles Flatpak." "$arg")"
				return 1
			fi
		fi

		if ! bo_winpath "$bdir" "$path"; then
			bo_open_fail "$(bo_msg "No drive in the bottle \"%s\" reaches %s." "$bottle" "$path")"
			return 1
		fi

		# With the switches Windows would use for this extension.
		ext="${path##*/}"
		ext="${ext##*.}"
		template=''
		[[ $path == */*.* ]] && template="$(awk -F'\t' -v id="$id" -v e="${ext,,}" \
			'$1 == id && $2 == e { print $3; exit }' "$BO_COMMANDS" 2>/dev/null)"
		_bo_win_args "$template" "$BO_WINPATH"
		winargs+=("${BO_WARGS[@]}")
	done

	case "$install" in
		native)  cmd=(bottles-cli) ;;
		flatpak) cmd=(flatpak run --command=bottles-cli "$BO_FLATPAK_ID") ;;
		*)
			bo_open_fail "$(bo_msg "This launcher is out of date. Run \"bottles-opener apply\" and try again.")"
			return 1
			;;
	esac

	cmd+=(run -b "$bottle")
	if bo_cli_has_program_id "$install"; then
		cmd+=(--program-id "$pid")
	else
		cmd+=(-p "$pname")
	fi
	cmd+=(-- "${winargs[@]}")

	if [[ -n ${BO_DRY_RUN:-} ]]; then
		printf '%q ' "${cmd[@]}"
		printf '\n'
		return 0
	fi

	exec "${cmd[@]}"
}
