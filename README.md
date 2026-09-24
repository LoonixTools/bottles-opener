<p align="center">
  <img width="200" src="res/bottles-opener.svg" alt="bottles-opener">
</p>

<h1 align="center">bottles-opener</h1>

<h3 align="center">Double-click a file and it opens in its Windows program, inside its bottle.</h3>

<p align="center">
  Works with FL Studio, Microsoft Office, Photoshop, Ableton and anything else you run through <a href="https://usebottles.com">Bottles</a>.
</p>

<h5 align="center">
  <a href="#how-to-use">How to use</a> |
  <a href="#how-to-install">Install</a> |
  <a href="https://github.com/LoonixTools/bottles-opener/issues">Report a bug</a>
</h5>

<p align="center">
  <a href="https://buymeacoffee.com/felitendo"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="48"></a>
</p>

You install FL Studio in Bottles, double-click your `.flp` and... your file manager asks what an `.flp` is. This tool reads which files your Windows programs registered in their bottle. That is the same list Windows uses. It teaches your system those types, gives them the program's icons and hands the file over the way Explorer would. One command and your files _✨just open✨_ (like on windows).

## How to use

Just run `bottles-opener`:

<p align="center">
  <img src="res/screenshots/menu.png" alt="The bottles-opener menu in Konsole: file opening on, 5 programs in 3 bottles" width="620">
</p>

Press `[1]` and you're done. `[3]` lists every file type and lets you pick what opens it:

<p align="center">
  <img src="res/screenshots/file-types.png" alt="The file types list in Konsole: .flp opens in FL Studio on a double-click, Office types are under Open With" width="620">
</p>

`double-click` opens it. `Open With` only lists it in the right-click menu. Types that already have an app on your system get this (like `.docx` with LibreOffice), so nothing you picked gets taken away. Space switches.

`[4]` lists your programs; Enter edits their file types, so you can add any extension you like. Or without the menu:

```bash
bottles-opener add flp,fst "FL Studio"
```

## How to install

**Arch**

```bash
yay -S bottles-opener
bottles-opener enable
```

**From source**

```bash
make
sudo make install
bottles-opener enable
```

No root? `make install PREFIX=~/.local` works too.

Needs `bash`, `python3` with PyYAML and icoextract (Bottles needs both itself) and `update-mime-database`.

## Features

- **Which files:** read from the bottle's registry, like Windows does (`.flp` → `FL64.flp.26` → `FL64.exe "%1"`). Programs that registered nothing are matched against a built-in list: all of Office, FL Studio, Ableton, Cubase, Photoshop, Illustrator, Affinity, AutoCAD, SketchUp and more.
- **Unknown extensions** (`.flp`, `.msg`, `.als`, ...) get a MIME type in `~/.local/share/mime/packages/bottles-opener.xml`, named like in Windows ("FL Studio project file"). Where Linux means something else by an extension (`.mpp` is Musepack, `.fst` a tracker module) the file's signature tells them apart.
- **Icons:** the file gets the icon Windows shows, pulled out of the program. A type your system already knows keeps its icon until the program is its default.
- **Opening:** the path becomes the Windows path (`Z:\home\you\song.flp`), with the switches from the registry (Outlook `/f`, PowerPoint shows `/s`), started through `bottles-cli` with all your bottle's settings.
- **Flatpak Bottles:** the file goes through the document portal first, like `flatpak run --file-forwarding`.

Everything written is recorded, so `bottles-opener disable` puts back exactly what was there. New programs are picked up by a systemd path unit; `bottles-opener apply` does the same by hand.

## Why not just Bottles?

Bottles 67 has "File Associations" per program, but it rejects extensions your system doesn't know (so `.flp`, `.msg`, `.als` are "invalid"), passes Linux paths, doesn't know which program opens what and doesn't touch icons.

## Commands

| Command | |
|---|---|
| `bottles-opener` | Interactive menu |
| `… enable` | Turn on, apply, start watching |
| `… disable` | Undo everything |
| `… apply` | Pick up new programs |
| `… apply --rebuild` | Redo from scratch |
| `… status` | What's set up |
| `… list` | All file types and what opens them |
| `… programs` | All programs and their file types |
| `… add <ext,...> <program> [bottle]` | Open file types with a program |
| `… remove <ext,...> [program]` | Stop opening file types |

## Building from source

```bash
make
sudo make install
```

Optionally needs `msgfmt` (gettext) and `scdoc`. Supports `PREFIX` and `DESTDIR`. `make check` runs syntax checks and shellcheck.

## License

GPL-3.0-or-later.
