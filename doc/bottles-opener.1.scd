bottles-opener(1)

# NAME

bottles-opener - double-click a file and it opens in its Windows program, inside its bottle

# SYNOPSIS

*bottles-opener* [_command_]

# DESCRIPTION

Sets up file opening for programs installed with Bottles: which files each
program opens, the MIME types the system is missing for them, their icons, and
a launcher that hands a file over as the Windows path the program expects.

Without a command it shows an interactive menu. Nothing outside the user's home
is written to; running as root is refused.

# COMMANDS

*enable*
	Turn on, set up every file type, start watching for new programs.

*disable*
	Turn off and put back everything that was changed, including the
	previous default application of each type.

*apply* [*--rebuild*]
	Set up what appeared since the last run. *--rebuild* takes everything
	back first and writes it again.

*status*
	What is set up.

*list*
	Every file type and what opens it.

*programs*
	Every program and the file types it opens.

*add* _ext_[,_ext_...] _program_ [_bottle_] [*--open-with*|*--default*]
	Open file types with a program, named as Bottles lists it or by id.

*remove* _ext_[,_ext_...] [_program_ [_bottle_]]
	Stop opening file types. A detected type is switched off rather than
	forgotten, so it does not come back.

*-h*, *--help*, *-V*, *--version*
	Help and version.

# FILE TYPES

Found in three places, later ones winning:

. The bottle's registry, as Windows reads it: extension, ProgID (following
  *CurVer*), the default verb's command, *DefaultIcon* and *FriendlyTypeName*.
. A built-in list for programs that registered nothing: Microsoft Office,
  FL Studio, Ableton Live, Cubase, Photoshop, AutoCAD and others.
. What was set by hand, in the menu or with *add* and *remove*.

Each type is *double-click* (the default application), *Open With* (only
offered there) or *off*. A detected type the system does not know becomes the
default; one it knows only gets *Open With*, since another application has it.
If the default is changed in the desktop's settings later, that choice stays.

An extension the system does not know gets a MIME type in
_~/.local/share/mime/packages/bottles-opener.xml_, described as in Windows.
Where the system uses an extension for something else (*.mpp*, *.fst*, *.gp*,
*.gpx*), the type is defined anyway, with the file's signature to tell the two
apart.

# ICONS

A file gets the icon Windows shows for it: *DefaultIcon* extracted from the
program with icoextract, or the icon Bottles saved for the program. It is
installed into the hicolor theme under a name of this program's own.

A type the system knows keeps its icon until the program is its default. It is
then copied whole into the package with the new icon, because Qt and GLib read
a type's description from the first directory that defines it.

# OPENING

The launcher, _~/.local/share/applications/bottles-opener-_id_.desktop_, is
hidden from menus and runs *bottles-opener open*. The file's path is mapped
through the bottle's drive letters (*C:* inside the bottle, *Z:* for the rest)
and passed with the registry's switches for its extension, e.g. Outlook's
*/f* or PowerPoint's */s*. A command Windows completes over DDE gets only the
file. The program is started with *bottles-cli run*.

With the Bottles Flatpak a file outside the bottle is exported through the
document portal first. The program can write that file, but nothing next to it.

# NEW PROGRAMS

A systemd user path unit watches the bottles directories, each _bottle.yml_
and the system's MIME packages. Without a systemd user session, run *apply*.

# FILES

_~/.config/bottles-opener/config_, _~/.config/bottles-opener/types_
	Settings and types changed by hand.

_~/.local/state/bottles-opener/_
	*ledger* (every change, for *disable*), *launchers* and *commands* (read
	by *open*).

_~/.cache/bottles-opener/_
	Parsed registries and extracted icons. Safe to delete.

# ENVIRONMENT

*NO_COLOR*
	Disables colour.

# REQUIREMENTS

Bash 4.2+, coreutils, Python 3 with PyYAML and icoextract (both Bottles
dependencies), *update-mime-database*. Optional: *notify-send*.

# SEE ALSO

*bottles-cli*(1), *update-mime-database*(1), *flatpak-document-export*(1)

# AUTHORS

Felitendo. https://github.com/Felitendo/bottles-opener
