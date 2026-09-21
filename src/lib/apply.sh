# shellcheck shell=bash
#
# Writing it all down, and taking it back.
#
# bo_apply converges: works out what should exist, writes what differs, takes
# back what the ledger has and is no longer wanted. Idempotent, so the watcher
# can call it any time. Undoing is converging on nothing.

BO_CHANGES=0

# Stable, unique per program, nothing to quote.
bo_launcher_id() {
	printf '%s\t%s' "$1" "$2" | sha1sum | cut -c1-12
}

# _bo_entry_escape <string>
# A desktop entry value. The scan already removed newlines.
_bo_entry_escape() {
	printf '%s' "${1//\\/\\\\}"
}

# _bo_exec_arg <string>
# One Exec argument, escaped for both layers: string value and Exec quoting.
_bo_exec_arg() {
	local s="$1"

	s="${s//%/%%}"
	if [[ $s =~ ^[A-Za-z0-9_./+%-]+$ ]]; then
		printf '%s' "$s"
		return
	fi

	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	s="${s//\`/\\\`}"
	s="${s//\$/\\\$}"
	# and the string layer on top
	s="${s//\\/\\\\}"
	printf '"%s"' "$s"
}

# bo_launcher_entry <program index> <MIME types; separated> <launcher id> <display name>
bo_launcher_entry() {
	local i="$1" mimes="$2" id="$3" name="$4" icon exe wmclass comment

	icon="${BO_P_ICON[i]}"
	if [[ $icon == /* && ! -f $icon ]] || [[ -z $icon ]]; then
		icon="com.usebottles.bottles"
	fi

	exe="${BO_P_PATH[i]//\\//}"
	exe="${exe##*/}"
	wmclass="${exe,,}"

	comment="$(bo_msg "Opens files in %s from the bottle \"%s\"" "${BO_P_NAME[i]}" "${BO_P_BOTTLE[i]}")"

	printf '[Desktop Entry]\n'
	printf 'Type=Application\n'
	printf 'Name=%s\n' "$(_bo_entry_escape "$name")"
	printf 'Comment=%s\n' "$(_bo_entry_escape "$comment")"
	printf 'Icon=%s\n' "$(_bo_entry_escape "$icon")"
	printf 'Exec=%s open %s %%f\n' "$(_bo_exec_arg "$BO_SELF")" "$id"
	printf 'Terminal=false\n'
	# Hidden: Bottles has the menu entry. Still opens its types and shows under
	# "Open With", as the spec intends.
	printf 'NoDisplay=true\n'
	printf 'MimeType=%s\n' "$mimes"
	[[ -n $wmclass ]] && printf 'StartupWMClass=%s\n' "$(_bo_entry_escape "$wmclass")"
	printf 'X-Bottles-Opener-Id=%s\n' "$id"
}

# _bo_owned <path>
# Ours to overwrite: in the ledger, or carrying our mark (a lost ledger).
# Icons have no mark.
_bo_owned() {
	local path="$1"
	[[ -e $path ]] || return 0
	bo_ledger_has file "$path" && return 0
	case "$path" in
		*.desktop) grep -q '^X-Bottles-Opener-Id=' "$path" 2>/dev/null ;;
		*.xml)     grep -q 'Written by bottles-opener' "$path" 2>/dev/null ;;
		*)         return 1 ;;
	esac
}

# _bo_file_put <path> <content>
# Writes and records a file of ours. Never overwrites somebody else's.
_bo_file_put() {
	local path="$1" content="$2" rc

	if ! _bo_owned "$path"; then
		bo_bad "$(bo_msg "Not overwriting %s - it was not written by this program." "$path")"
		return 1
	fi

	bo_write_if_changed "$path" "$content"
	rc=$?
	(( rc == 2 )) && return 1
	(( rc == 0 )) && _bo_mark_dirty "$path"
	bo_ledger_add file "$path"
	return 0
}

# _bo_file_copy <path> <source>
_bo_file_copy() {
	local path="$1" src="$2"

	_bo_owned "$path" || return 1

	if ! cmp -s -- "$src" "$path" 2>/dev/null; then
		mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
		cp -f -- "$src" "$path" 2>/dev/null || return 1
		_bo_mark_dirty "$path"
	fi
	bo_ledger_add file "$path"
}

# What changed, so only those caches are rebuilt. BO_CHANGES: any of it.
BO_DIRTY_MIME=0
BO_DIRTY_APPS=0
BO_DIRTY_ICONS=0

_bo_mark_dirty() {
	BO_CHANGES=1
	case "$1" in
		"$BO_MIMEPKG") BO_DIRTY_MIME=1 ;;
		"$BO_APPDIR"/*) BO_DIRTY_APPS=1 ;;
		"$BO_ICONDIR"/*) BO_DIRTY_ICONS=1 ;;
	esac
}

# bo_icons_changed
# KIconLoader's iconChanged signal.
bo_icons_changed() {
	if bo_have dbus-send; then
		dbus-send --session --type=signal /KIconLoader \
			org.kde.KIconLoader.iconChanged int32:0 > /dev/null 2>&1 || true
	elif bo_have gdbus; then
		gdbus emit --session --object-path /KIconLoader \
			--signal org.kde.KIconLoader.iconChanged 0 > /dev/null 2>&1 || true
	fi
}

# bo_refresh
# Rebuilds the desktop's caches. Every tool is optional.
bo_refresh() {
	if (( BO_DIRTY_MIME )) && bo_have update-mime-database; then
		mkdir -p "$BO_MIMEDIR/packages" 2>/dev/null
		update-mime-database "$BO_MIMEDIR" > /dev/null 2>&1 || true
	fi

	if (( BO_DIRTY_APPS )) && bo_have update-desktop-database; then
		update-desktop-database "$BO_APPDIR" > /dev/null 2>&1 || true
	fi

	if (( BO_DIRTY_ICONS )) && [[ -d $BO_ICONDIR ]] && bo_have gtk-update-icon-cache; then
		# The user's hicolor has no index.theme of its own, hence -t.
		gtk-update-icon-cache -q -t -f "$BO_ICONDIR" > /dev/null 2>&1 || true
	fi

	# Running KDE apps remember icons they did not find; this makes them look
	# again, as System Settings does after an icon theme change.
	if (( BO_DIRTY_ICONS )); then
		bo_icons_changed
	fi

	# KDE's cache, rebuilt now rather than eventually.
	if (( BO_DIRTY_MIME || BO_DIRTY_APPS )); then
		local k
		for k in kbuildsycoca6 kbuildsycoca5; do
			if bo_have "$k"; then
				"$k" > /dev/null 2>&1 || true
				break
			fi
		done
	fi

	BO_DIRTY_MIME=0; BO_DIRTY_APPS=0; BO_DIRTY_ICONS=0
}

# bo_apply
bo_apply() {
	local k i ext mime id path name src
	local -a want_files=() launcher_lines=() command_lines=()
	declare -A prog_mimes=() lid=() defaults=() default_prog=() names=() dup=()
	declare -A icon_src=() icon_idx=() icon_prog=() icon_rank=()
	declare -A BO_PKG_DESC=() BO_PKG_MAGIC=() BO_PKG_GICON=() BO_PKG_GLOBS=() BO_PKG_ICON=()
	BO_PKG_ORDER=()

	BO_CHANGES=0
	bo_config_load
	bo_assoc_compute

	# Unreadable looks like empty, and converging on empty removes everything.
	if [[ -n $BO_SCAN_ERROR ]]; then
		bo_bad "$(bo_msg "Bottles could not be read - is python3 with PyYAML installed? Nothing was changed.")"
		return 1
	fi

	for k in "${BO_A_ORDER[@]}"; do
		i="${BO_A_PIDX[k]}"
		[[ ${BO_A_STATE[k]} != off && $i -ge 0 ]] || continue
		ext="${BO_A_EXT[k]}"

		bo_mime_for "$ext"
		mime="$BO_MIME"

		[[ -n ${lid[$i]:-} ]] || lid[$i]="$(bo_launcher_id "${BO_P_INSTALL[i]}" "${BO_P_ID[i]}")"
		[[ ";${prog_mimes[$i]:-}" == *";$mime;"* ]] || prog_mimes[$i]+="$mime;"

		if [[ ${BO_A_STATE[k]} == default && -z ${default_prog[$mime]:-} ]]; then
			default_prog[$mime]="$i"
		fi

		# How Windows starts the program for this extension.
		[[ -n ${BO_A_ARGS[k]} ]] \
			&& command_lines+=("${lid[$i]}"$'\t'"$ext"$'\t'"${BO_A_ARGS[k]}")

		if (( BO_MIME_OWN )); then
			if [[ -z ${BO_PKG_DESC[$mime]+set} ]]; then
				bo_known_type "$ext"
				BO_PKG_ORDER+=("$mime")
				BO_PKG_DESC[$mime]="${BO_A_DESC[k]:-$BO_KT_DESC}"
				BO_PKG_MAGIC[$mime]="$BO_KT_MAGIC"
				BO_PKG_GICON[$mime]="$BO_KT_ICON"
				BO_PKG_GLOBS[$mime]=''
			fi
			[[ " ${BO_PKG_GLOBS[$mime]} " == *" $ext "* ]] \
				|| BO_PKG_GLOBS[$mime]+="${BO_PKG_GLOBS[$mime]:+ }$ext"
		fi

		# As in Windows: the icon of the default program. A system type keeps
		# its own until then; one of ours takes the first program's.
		if [[ $CFG_ICONS == yes ]] && { (( BO_MIME_OWN )) || [[ ${BO_A_STATE[k]} == default ]]; }; then
			local rank=1
			[[ ${BO_A_STATE[k]} == default ]] && rank=2
			[[ -n ${BO_A_ICON[k]} ]] && rank=$(( rank + 2 ))
			if (( rank > ${icon_rank[$mime]:-0} )); then
				icon_rank[$mime]=$rank
				icon_prog[$mime]=$i
				if [[ -n ${BO_A_ICON[k]} ]]; then
					icon_src[$mime]="${BO_A_ICON[k]}"; icon_idx[$mime]="${BO_A_IDX[k]}"
				else
					icon_src[$mime]="${BO_P_ICON[i]}"; icon_idx[$mime]=0
				fi
			fi
		fi
	done

	# The same name twice in "Open With" gets the bottle added.
	for i in "${!prog_mimes[@]}"; do
		name="${BO_P_NAME[i]}"
		[[ -n ${names[$name]+set} ]] && dup[$name]=1
		names[$name]=1
	done

	# Icons. A system type goes into the package just for its icon.
	for mime in "${!icon_src[@]}"; do
		i="${icon_prog[$mime]}"
		src="${icon_src[$mime]}"
		# No Windows icon to be had: the program's own, as Bottles saved it.
		if ! bo_icon_png "${BO_P_INSTALL[i]}" "$src" "${icon_idx[$mime]}"; then
			[[ $src != "${BO_P_ICON[i]}" ]] || continue
			bo_icon_png "${BO_P_INSTALL[i]}" "${BO_P_ICON[i]}" 0 || continue
		fi
		bo_icon_target "$mime" "$BO_ICON_PNG" || continue
		_bo_file_copy "$BO_ICON_TARGET" "$BO_ICON_PNG" || continue
		want_files+=("$BO_ICON_TARGET")
		BO_PKG_ICON[$mime]="$BO_ICON_NAME"
		[[ -n ${BO_PKG_DESC[$mime]+set} ]] || BO_PKG_ORDER+=("$mime")
	done

	if (( ${#BO_PKG_ORDER[@]} )); then
		_bo_file_put "$BO_MIMEPKG" "$(bo_mime_package)" && want_files+=("$BO_MIMEPKG")
	fi

	# The launchers.
	for i in "${!prog_mimes[@]}"; do
		id="${lid[$i]}"
		path="$BO_APPDIR/bottles-opener-$id.desktop"
		name="${BO_P_NAME[i]}"
		[[ -n ${dup[$name]+set} ]] && name="$name (${BO_P_BOTTLE[i]})"

		_bo_file_put "$path" "$(bo_launcher_entry "$i" "${prog_mimes[$i]}" "$id" "$name")" \
			|| continue
		want_files+=("$path")

		launcher_lines+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$id" "${BO_P_INSTALL[i]}" \
			"${BO_P_ID[i]}" "${BO_P_BOTTLE[i]}" "${BO_P_BDIR[i]}" "${BO_P_NAME[i]}")")

		for mime in "${!default_prog[@]}"; do
			[[ ${default_prog[$mime]} == "$i" ]] && defaults[$mime]="bottles-opener-$id.desktop"
		done
	done

	# What `open` reads.
	mkdir -p "$BO_STATEDIR" 2>/dev/null
	if (( ${#launcher_lines[@]} )); then
		printf '%s\n' "${launcher_lines[@]}" > "$BO_LAUNCHERS"
	else
		rm -f -- "$BO_LAUNCHERS"
	fi
	if (( ${#command_lines[@]} )); then
		printf '%s\n' "${command_lines[@]}" > "$BO_COMMANDS"
	else
		rm -f -- "$BO_COMMANDS"
	fi

	_bo_prune_files "${want_files[@]}"

	# Defaults, once the launchers they name exist.
	for mime in "${!defaults[@]}"; do
		_bo_default_set "$mime" "${defaults[$mime]};"
	done
	local m
	while IFS= read -r m; do
		[[ -n $m && -z ${defaults[$m]:-} ]] && _bo_default_restore "$m"
	done < <(bo_ledger_list default)

	bo_refresh

	bo_assoc_counts
	bo_state_write last_apply "$(date +%s)"
	return 0
}

# _bo_prune_files <wanted path>...
_bo_prune_files() {
	local f w keep
	while IFS= read -r f; do
		[[ -n $f ]] || continue
		keep=0
		for w in "$@"; do
			[[ $w == "$f" ]] && { keep=1; break; }
		done
		(( keep )) && continue

		# Only the file; the directory may have been there before.
		if [[ -e $f ]]; then
			rm -f -- "$f" && _bo_mark_dirty "$f"
		fi
		bo_ledger_forget file "$f"
	done < <(bo_ledger_list file)
}

# _bo_default_set <MIME type> <value>
_bo_default_set() {
	local mime="$1" value="$2" current

	current="$(bo_mimeapps_get "$mime")"
	[[ $current == "$value" ]] && { bo_ledger_add default "$mime" "-"; return 0; }

	# Set here before, changed since in the desktop's settings: that choice
	# stands. See bo_default_claim.
	if [[ -n $current ]] && ! bo_is_ours "$current" && bo_ledger_has default "$mime"; then
		return 0
	fi

	# What was there before, unless one of ours.
	if bo_is_ours "$current" || [[ -z $current ]]; then
		bo_ledger_add default "$mime" "-"
	else
		bo_ledger_add default "$mime" "$current"
	fi

	bo_mimeapps_set "$mime" "$value" && { BO_CHANGES=1; BO_DIRTY_APPS=1; }
}

# bo_default_claim <extension>
# Made the default by hand: take the type back even from a later choice, by
# forgetting the record. The next apply records the current one instead.
bo_default_claim() {
	local current

	bo_mime_for "$1"
	current="$(bo_mimeapps_get "$BO_MIME")"
	# Still ours: keep the record of what came first.
	bo_is_ours "$current" && return 0
	bo_ledger_forget default "$BO_MIME"
}

# _bo_default_restore <MIME type>
# Puts back what was there, if the default is still ours.
_bo_default_restore() {
	local mime="$1" prev current

	prev="$(bo_ledger_detail default "$mime")"
	current="$(bo_mimeapps_get "$mime")"

	if bo_is_ours "$current"; then
		[[ $prev == "-" ]] && prev=''
		bo_mimeapps_set "$mime" "$prev" && { BO_CHANGES=1; BO_DIRTY_APPS=1; }
	fi
	bo_ledger_forget default "$mime"
}

# bo_revert
# Takes back every recorded change.
bo_revert() {
	local m

	BO_CHANGES=0
	_bo_prune_files
	while IFS= read -r m; do
		[[ -n $m ]] && _bo_default_restore "$m"
	done < <(bo_ledger_list default)
	rm -f -- "$BO_LAUNCHERS" "$BO_COMMANDS"
	[[ -s $BO_LEDGER ]] || rm -f -- "$BO_LEDGER"

	bo_refresh
	return 0
}

# ---------------------------------------------------------------------------
# The watcher
# ---------------------------------------------------------------------------
# A systemd path unit on the bottles directories and every bottle.yml. What the
# shipped unit cannot know goes into a drop-in.

BO_UNIT_PATH="bottles-opener.path"
BO_UNIT_SERVICE="bottles-opener.service"
BO_UNIT_DROPIN="${BO_XDG_CONFIG}/systemd/user/${BO_UNIT_PATH}.d"

bo_watch_available() {
	[[ -z ${BO_NO_WATCH:-} ]] || return 1
	bo_have systemctl && [[ -n ${XDG_RUNTIME_DIR:-} || -S "/run/user/$(id -u)/bus" ]]
}

bo_watch_enabled() {
	bo_watch_available || return 1
	systemctl --user is-enabled --quiet "$BO_UNIT_PATH" 2>/dev/null
}

# _bo_watch_dropin_write
# 0 when it changed and systemd needs a reload, 1 when not.
_bo_watch_dropin_write() {
	local content="[Path]"$'\n' p

	bo_scan_once
	for p in "${BO_ROOTS[@]}"; do
		# The unit watches the default places already.
		[[ $p == "$HOME/.local/share/bottles/bottles" ]] && continue
		[[ $p == "$HOME/.var/app/$BO_FLATPAK_ID/data/bottles/bottles" ]] && continue
		# % is a unit file specifier.
		content+="PathModified=${p//%/%%}"$'\n'
	done
	for p in "${BO_CONFS[@]}"; do
		content+="PathChanged=${p//%/%%}"$'\n'
	done

	bo_write_if_changed "$BO_UNIT_DROPIN/bottles.conf" "$content"
}

_bo_watch_dropin_remove() {
	[[ -e "$BO_UNIT_DROPIN/bottles.conf" ]] || return 1
	rm -f -- "$BO_UNIT_DROPIN/bottles.conf"
	rmdir "$BO_UNIT_DROPIN" 2>/dev/null || true
	return 0
}

bo_watch_enable() {
	bo_watch_available || return 1
	_bo_watch_dropin_write
	systemctl --user daemon-reload > /dev/null 2>&1 || true
	systemctl --user enable --now "$BO_UNIT_PATH" > /dev/null 2>&1 || return 1
	return 0
}

# bo_watch_refresh
# Keeps a running watcher in step with the bottles that exist now.
bo_watch_refresh() {
	bo_watch_available || return 0
	_bo_watch_dropin_write || return 0
	systemctl --user daemon-reload > /dev/null 2>&1 || true
	systemctl --user restart "$BO_UNIT_PATH" > /dev/null 2>&1 || true
	return 0
}

bo_watch_disable() {
	bo_watch_available || return 0
	systemctl --user disable --now "$BO_UNIT_PATH" > /dev/null 2>&1 || true
	_bo_watch_dropin_remove && systemctl --user daemon-reload > /dev/null 2>&1
	return 0
}
