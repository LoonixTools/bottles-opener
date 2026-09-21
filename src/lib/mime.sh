# shellcheck shell=bash
#
# File types: what the system already knows, what has to be taught to it, and
# which application opens what.
#
# Launchers claim MIME types, not extensions. An unknown extension is
# octet-stream like every unknown file, so it gets a type of its own here.

# Extension -> MIME type from the compiled globs2 files, minus our own types.
declare -A BO_SYS_MIME=()
BO_SYS_MIME_LOADED=0

bo_mime_system_load() {
	local own='' dirs dir files=() ext mime

	(( BO_SYS_MIME_LOADED )) && return 0
	BO_SYS_MIME_LOADED=1
	BO_SYS_MIME=()

	# The types defined in our own package, space separated.
	if [[ -r $BO_MIMEPKG ]]; then
		own=" $(sed -n 's/.*<mime-type type="\([^"]*\)".*/\1/p' "$BO_MIMEPKG" | tr '\n' ' ')"
	fi

	[[ -r $BO_MIMEDIR/globs2 ]] && files+=("$BO_MIMEDIR/globs2")
	IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
	for dir in "${dirs[@]}"; do
		[[ -n $dir && -r $dir/mime/globs2 ]] && files+=("$dir/mime/globs2")
	done
	(( ${#files[@]} )) || return 0

	# weight:type:glob[:flags]; plain "*.ext" only, heaviest wins.
	while IFS=$'\t' read -r ext mime; do
		BO_SYS_MIME[$ext]="$mime"
	# Ours can only be in the user's database.
	done < <(awk -F: -v own="$own" -v userfile="$BO_MIMEDIR/globs2" '
		/^#/ { next }
		{
			weight = $1 + 0; type = $2; glob = $3
			if (FILENAME == userfile && index(own, " " type " ")) next
			if (glob !~ /^\*\.[^*?[\]\/]+$/) next
			ext = tolower(substr(glob, 3))
			if (!(ext in best) || weight > best[ext]) { best[ext] = weight; seen[ext] = type }
		}
		END { for (e in seen) printf "%s\t%s\n", e, seen[e] }
	' "${files[@]}" 2>/dev/null)
}

# bo_mime_for <extension>
# BO_MIME: the type the extension is claimed as. BO_MIME_OWN: 1 when this
# program defines that type.
BO_MIME=''
BO_MIME_OWN=0

bo_mime_for() {
	local ext="$1"

	bo_mime_system_load

	if bo_known_type "$ext" && (( BO_KT_OWN )); then
		BO_MIME="$BO_KT_MIME"
		BO_MIME_OWN=1
	elif [[ -n ${BO_SYS_MIME[$ext]:-} ]]; then
		BO_MIME="${BO_SYS_MIME[$ext]}"
		BO_MIME_OWN=0
	else
		bo_known_type "$ext"
		BO_MIME="$BO_KT_MIME"
		BO_MIME_OWN=1
	fi
}

# bo_ext_valid <extension>
# Bottles' own rule.
bo_ext_valid() {
	[[ $1 =~ ^[a-z0-9][a-z0-9_+-]{0,31}$ ]]
}

# bo_ext_normalize <input>
# ".FLP", "*.flp" and "flp" all mean the same thing. Result in BO_EXT.
BO_EXT=''

bo_ext_normalize() {
	local e="${1,,}"
	e="${e#\*}"
	e="${e#.}"
	BO_EXT="$e"
	bo_ext_valid "$e"
}

_bo_xml() {
	local s="$1"
	s="${s//&/&amp;}"
	s="${s//</&lt;}"
	s="${s//>/&gt;}"
	s="${s//\"/&quot;}"
	printf '%s' "$s"
}

# _bo_system_type_xml <MIME type>
# The system's own definition of a type, as update-mime-database wrote it.
_bo_system_type_xml() {
	local dir f
	local -a dirs
	IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
	for dir in "${dirs[@]}"; do
		for f in "$dir/mime/$1.xml" "$dir/mime/${1,,}.xml"; do
			[[ -r $f ]] && { printf '%s\n' "$f"; return 0; }
		done
	done
	return 1
}

# _bo_magic_xml <spec>
_bo_magic_xml() {
	local kind="${1%%:*}" value="${1#*:}"
	[[ -n $1 ]] || return 0
	printf '    <magic priority="50">\n'
	printf '      <match type="%s" offset="0" value="%s"/>\n' "$kind" "$(_bo_xml "$value")"
	printf '    </magic>\n'
}

# bo_mime_package
# Every type in BO_PKG_ORDER, from BO_PKG_* set by bo_apply. A system type is
# copied whole with ours added: Qt and GLib read the description from the
# first directory defining the type, and the user's comes first.
bo_mime_package() {
	local mime ext extra sysxml

	printf '<?xml version="1.0" encoding="UTF-8"?>\n'
	printf '<!-- Written by bottles-opener. Taken back by `bottles-opener disable`. -->\n'
	printf '<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">\n'

	for mime in "${BO_PKG_ORDER[@]}"; do
		extra=''
		for ext in ${BO_PKG_GLOBS[$mime]:-}; do
			extra+="    <glob pattern=\"*.$(_bo_xml "$ext")\"/>"$'\n'
		done
		extra+="$(_bo_magic_xml "${BO_PKG_MAGIC[$mime]:-}")"
		[[ -n ${BO_PKG_MAGIC[$mime]:-} ]] && extra+=$'\n'
		if [[ -n ${BO_PKG_ICON[$mime]:-} ]]; then
			extra+="    <icon name=\"$(_bo_xml "${BO_PKG_ICON[$mime]}")\"/>"$'\n'
		fi

		if sysxml="$(_bo_system_type_xml "$mime")"; then
			awk -v extra="$extra" '
				/^<\?xml/ || /<!--.*-->/ || /^[[:space:]]*<icon[[:space:]]/ { next }
				/<\/mime-type>/ { printf "%s", extra; print "  " $0; next }
				{ print "  " $0 }
			' "$sysxml"
		else
			printf '  <mime-type type="%s">\n' "$(_bo_xml "$mime")"
			printf '    <comment>%s</comment>\n' "$(_bo_xml "${BO_PKG_DESC[$mime]}")"
			printf '    <generic-icon name="%s"/>\n' "$(_bo_xml "${BO_PKG_GICON[$mime]}")"
			printf '%s' "$extra"
			printf '  </mime-type>\n'
		fi
	done

	printf '</mime-info>\n'
}

# ---------------------------------------------------------------------------
# Icons
# ---------------------------------------------------------------------------
# Files get the icon Windows shows for them, installed into hicolor.

# bo_png_size <file>
# A PNG's width, from its header.
bo_png_size() {
	local -a b
	read -ra b < <(od -An -tu1 -j0 -N24 -- "$1" 2>/dev/null | tr -s ' \n' '  ')
	(( ${#b[@]} >= 24 )) || return 1
	# \x89 P N G
	(( b[0] == 137 && b[1] == 80 && b[2] == 78 && b[3] == 71 )) || return 1
	printf '%d\n' $(( (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19] ))
}

# bo_icon_target <MIME type> <png>
# BO_ICON_NAME and BO_ICON_TARGET; 1 for an unusable png. Our own name: a theme
# would win over hicolor for the type's standard one.
BO_ICON_TARGET=''
BO_ICON_NAME=''

bo_icon_target() {
	local mime="$1" src="$2" size s dir=''

	BO_ICON_TARGET=''
	[[ $src == /* && -f $src ]] || return 1
	size="$(bo_png_size "$src")" || return 1

	# The largest theme size the icon still fills.
	for s in 16 22 24 32 48 64 128 256 512; do
		(( size >= s )) && dir="${s}x${s}"
	done
	[[ -n $dir ]] || return 1

	BO_ICON_NAME="bottles-opener-${mime//\//-}"
	BO_ICON_TARGET="$BO_ICONDIR/$dir/mimetypes/$BO_ICON_NAME.png"
}

# bo_icon_png <install> <file> <index>
# The icon as PNG in BO_ICON_PNG; extracted once, then cached.
BO_ICON_PNG=''

bo_icon_png() {
	local install="$1" src="$2" idx="${3:-0}" key out rc

	BO_ICON_PNG=''
	[[ -f $src ]] || return 1
	if [[ ${src,,} == *.png ]]; then
		BO_ICON_PNG="$src"
		return 0
	fi

	key="$(printf '%s\t%s\t%s' "$src" "$idx" "$(stat -c '%s.%Y' -- "$src" 2>/dev/null)" \
		| sha1sum | cut -c1-16)"
	out="$BO_CACHEDIR/icons/$key.png"

	[[ -s $out ]] && { BO_ICON_PNG="$out"; return 0; }
	[[ -e $out.none ]] && return 1
	mkdir -p "$BO_CACHEDIR/icons" 2>/dev/null || return 1

	rc=127
	if bo_have python3; then
		python3 "$BO_LIBDIR/icon.py" "$src" "$idx" > "$out.tmp" 2>/dev/null
		rc=$?
	fi
	# The Flatpak surely has icoextract.
	if (( rc == 3 || rc == 127 )) && [[ $install == flatpak ]]; then
		flatpak run --command=python3 "$BO_FLATPAK_ID" - "$src" "$idx" \
			< "$BO_LIBDIR/icon.py" > "$out.tmp" 2>/dev/null
		rc=$?
	fi

	if (( rc == 0 )) && [[ -s $out.tmp ]]; then
		mv -f "$out.tmp" "$out"
		BO_ICON_PNG="$out"
		return 0
	fi
	rm -f "$out.tmp"
	# Remember only a missing icon, not a missing icoextract.
	(( rc == 4 )) && : > "$out.none"
	return 1
}

# ---------------------------------------------------------------------------
# mimeapps.list
# ---------------------------------------------------------------------------
# Edited line by line: the rest is somebody's settings.

# bo_mimeapps_get <MIME type>
bo_mimeapps_get() {
	[[ -r $BO_MIMEAPPS ]] || return 0
	awk -v key="$1" '
		/^[[:space:]]*\[/ { group = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", group); next }
		group == "[Default Applications]" {
			line = $0
			sub(/^[[:space:]]+/, "", line)
			if (index(line, key "=") == 1) { print substr(line, length(key) + 2); exit }
		}
	' "$BO_MIMEAPPS"
}

# bo_mimeapps_set <MIME type> <value>
# An empty value takes the line out.
bo_mimeapps_set() {
	local key="$1" value="$2" tmp file

	mkdir -p "$(dirname "$BO_MIMEAPPS")" || return 1
	[[ -e $BO_MIMEAPPS ]] || : > "$BO_MIMEAPPS" || return 1

	# Keep a dotfiles symlink: replace its target, not the link.
	file="$(readlink -f -- "$BO_MIMEAPPS")" || return 1

	tmp="$(mktemp "${file}.XXXXXX")" || return 1
	chmod --reference="$file" "$tmp" 2>/dev/null || chmod 0644 "$tmp"

	awk -v key="$key" -v value="$value" '
		function flush() {
			if (ingroup && !done && value != "") { print key "=" value; done = 1 }
		}
		/^[[:space:]]*\[/ {
			flush()
			group = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", group)
			ingroup = (group == "[Default Applications]")
			if (ingroup) seen = 1
			print; next
		}
		ingroup {
			line = $0
			sub(/^[[:space:]]+/, "", line)
			if (index(line, key "=") == 1) {
				if (!done && value != "") { print key "=" value; done = 1 }
				next
			}
		}
		{ print }
		END {
			flush()
			if (!seen && value != "") {
				print "[Default Applications]"
				print key "=" value
			}
		}
	' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }

	mv -f "$tmp" "$file"
}

# bo_is_ours <mimeapps value>
# Whether it names only one of our launchers.
bo_is_ours() {
	local v="${1%;}"
	[[ $v == bottles-opener-*.desktop && $v != *';'* ]]
}
