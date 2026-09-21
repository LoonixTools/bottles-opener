# bottles-opener: build and install
#
# Everything here is plain shell and one small Python script; "building" only
# means compiling the gettext catalogs and rendering the man page. Both targets
# degrade to a no-op when msgfmt/scdoc are missing, so the tree stays usable
# for development without the build dependencies installed.

# Overridable so a packager can pass the version it is actually building
# (`make VERSION=$pkgver`). The literal below is the fallback for builds
# straight from a checkout, and is what a release tag has to carry.
VERSION      ?= 0.1.0

PREFIX       ?= /usr
DESTDIR      ?=
BINDIR       ?= $(PREFIX)/bin
DATADIR      ?= $(PREFIX)/share
LIBDIR       ?= $(DATADIR)/bottles-opener/lib
LOCALEDIR    ?= $(DATADIR)/locale
MANDIR       ?= $(DATADIR)/man

# Where systemd looks for user units. For a normal install into /usr this is
# asked of systemd itself, because the answer is not the same everywhere, and
# only guessed at when there is no systemd installed to ask.
#
# A build with a prefix of its own keeps the units under that prefix instead,
# and under share rather than lib: $XDG_DATA_HOME/systemd/user is a search path
# and ~/.local/lib/systemd/user is not, so an install into ~/.local that put
# the units in lib would leave the watcher impossible to enable.
ifeq ($(PREFIX),/usr)
USERUNITDIR  ?= $(shell pkg-config --variable=systemduserunitdir systemd 2>/dev/null || echo /usr/lib/systemd/user)
else
USERUNITDIR  ?= $(DATADIR)/systemd/user
endif

LINGUAS      := de
MOFILES      := $(patsubst %,po/%.mo,$(LINGUAS))
MANPAGE      := doc/bottles-opener.1

LIBS         := $(wildcard src/lib/*.sh)

MSGFMT       := $(shell command -v msgfmt 2>/dev/null)
SCDOC        := $(shell command -v scdoc 2>/dev/null)

.PHONY: all build install uninstall check pot clean version

all: build

build: $(MOFILES) $(MANPAGE)

# The one place the version is written down, for everything that has to agree
# with it.
version:
	@echo $(VERSION)

po/%.mo: po/%.po
ifdef MSGFMT
	$(MSGFMT) --check --output-file=$@ $<
else
	@echo "msgfmt not found, skipping $@"
endif

$(MANPAGE): doc/bottles-opener.1.scd
ifdef SCDOC
	$(SCDOC) < $< > $@
else
	@echo "scdoc not found, skipping $@"
endif

# Regenerates the template from the sources. The setting labels live in an
# array rather than in a call xgettext can see, so they are listed in
# po/extra.pot and merged in.
pot:
	xgettext --language=Shell --from-code=UTF-8 -k --keyword=bo_msg --keyword=bo_msg_into \
		--package-name=bottles-opener --package-version=$(VERSION) \
		--msgid-bugs-address=https://github.com/LoonixTools/bottles-opener/issues \
		--add-comments=TRANSLATORS --no-location --sort-output \
		--output=po/bottles-opener.pot.tmp src/bottles-opener $(LIBS)
	msgcat --use-first --sort-output --output-file=po/bottles-opener.pot \
		po/bottles-opener.pot.tmp po/extra.pot
	rm -f po/bottles-opener.pot.tmp
	@for l in $(LINGUAS); do msgmerge --quiet --update --backup=none po/$$l.po po/bottles-opener.pot; done

# Syntax-check every shell file, and run shellcheck when it is available.
check:
	@set -e; for f in src/bottles-opener $(LIBS); do \
		bash -n "$$f" && echo "ok  $$f"; \
	done
	@for f in src/lib/*.py; do \
		python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$$f" && echo "ok  $$f"; \
	done
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x -e SC1090,SC1091 src/bottles-opener $(LIBS); \
		echo "ok  shellcheck"; \
	else \
		echo "shellcheck not found, skipped"; \
	fi
	@if command -v msgfmt >/dev/null 2>&1; then \
		for l in $(LINGUAS); do msgfmt --check --output-file=/dev/null po/$$l.po && echo "ok  po/$$l.po"; done; \
	fi

install: build
	# executable
	install -Dm755 src/bottles-opener "$(DESTDIR)$(BINDIR)/bottles-opener"

	# shell libraries and the scanner
	install -d "$(DESTDIR)$(LIBDIR)"
	install -Dm644 -t "$(DESTDIR)$(LIBDIR)" $(LIBS) src/lib/scan.py src/lib/icon.py

	# the version and the resolved paths are baked in at install time
	sed -i -e 's|@VERSION@|$(VERSION)|g' \
	       -e 's|@LIBDIR@|$(LIBDIR)|g' \
	       -e 's|@LOCALEDIR@|$(LOCALEDIR)|g' \
	       "$(DESTDIR)$(BINDIR)/bottles-opener" \
	       "$(DESTDIR)$(LIBDIR)"/*.sh

	# user units: the watcher, and the one-shot it starts
	install -Dm644 res/systemd/bottles-opener.service \
		"$(DESTDIR)$(USERUNITDIR)/bottles-opener.service"
	install -Dm644 res/systemd/bottles-opener.path \
		"$(DESTDIR)$(USERUNITDIR)/bottles-opener.path"
	sed -i -e 's|@BINDIR@|$(BINDIR)|g' \
		"$(DESTDIR)$(USERUNITDIR)/bottles-opener.service"

	# translations
	@for l in $(LINGUAS); do \
		if [ -f "po/$$l.mo" ]; then \
			install -Dm644 "po/$$l.mo" \
				"$(DESTDIR)$(LOCALEDIR)/$$l/LC_MESSAGES/bottles-opener.mo"; \
		fi; \
	done

	# documentation
	@if [ -f $(MANPAGE) ]; then \
		install -Dm644 $(MANPAGE) "$(DESTDIR)$(MANDIR)/man1/bottles-opener.1"; \
	fi
	install -Dm644 README.md \
		"$(DESTDIR)$(DATADIR)/doc/bottles-opener/README.md"

uninstall:
	rm -f  "$(DESTDIR)$(BINDIR)/bottles-opener"
	rm -rf "$(DESTDIR)$(DATADIR)/bottles-opener"
	rm -f  "$(DESTDIR)$(USERUNITDIR)/bottles-opener.service"
	rm -f  "$(DESTDIR)$(USERUNITDIR)/bottles-opener.path"
	rm -f  "$(DESTDIR)$(MANDIR)/man1/bottles-opener.1"
	rm -rf "$(DESTDIR)$(DATADIR)/doc/bottles-opener"
	@for l in $(LINGUAS); do \
		rm -f "$(DESTDIR)$(LOCALEDIR)/$$l/LC_MESSAGES/bottles-opener.mo"; \
	done

clean:
	rm -f po/*.mo $(MANPAGE)
