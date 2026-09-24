# CLAUDE.md

## Style

- Keep everything short: replies, explanations, comments, docs.
- Use simple English: short sentences, common words.
- Avoid em dashes (—). Do not just swap them for "-" either. Rewrite the sentence instead, for
  example with a comma, a colon, brackets or two sentences.

## Commits

- English only.
- Conventional Commits prefix: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`, `build:`.
- Subject as short as possible. Imperative, lowercase, no trailing period.
- Body only when something genuinely cannot be inferred from the diff.
- Never add `Co-Authored-By`, "Generated with" or any other AI attribution to commits or PR descriptions.

## Releases

Releases look like the ones of big projects such as Immich. `.github/release-notes.sh <tag>` builds
the notes: the entry from `CHANGELOG.md` (welcome and highlights), a support section, every commit
since the last release sorted by its prefix (`feat`, `fix`, `docs`, ...) with author and link, and
the full changelog link. So commit subjects end up in public: keep them clear.

1. Read `git log <last tag>..HEAD` and pick the version: only fixes → patch, something new → minor,
   something that breaks or needs the user to act → major.
2. Bump the version and add the entry at the top of `CHANGELOG.md`, in one commit (`chore: 1.4.0`).
3. Push, tag and create the release:
   ```bash
   git tag v1.4.0 && git push origin main v1.4.0
   gh release create v1.4.0 --title v1.4.0 --notes "$(.github/release-notes.sh v1.4.0)"
   ```
4. PKGBUILDS picks up the new release for the AUR on its own.

A minor or major release (has `### Highlights`, gets a heading and the support section):

```markdown
## v1.4.0

_2026-09-24_

Welcome to bottles-opener `v1.4.0`! One or two sentences on what this release is about.

<p align="center">
  <img width="480" alt="What the picture shows" src="https://raw.githubusercontent.com/LoonixTools/bottles-opener/v1.4.0/<path>">
</p>

### 🚨 Breaking changes

- Only if there are any: what changed, and what the user has to do.

### Highlights

- First highlight, a few words
- Second highlight
```

A picture under the welcome is optional. To show the menu or another screen of the program, use a
real screenshot of it running in Konsole, in English. Never a text copy of the screen. The same goes
for the README. The highlights stay a plain list: no heading or text per highlight, the list of
commits explains the rest.

A patch release is just a sentence or two, for example: "A small patch. The menu no longer closes
when you press Enter." The list of commits follows on its own.

- Write for users: what they notice, not how the code does it. Friendly and simple.
- Commands and settings they type go in backticks, buttons and labels in bold.
- To change an old release: edit its entry, commit, then
  `gh release edit <tag> --title <tag> --notes "$(.github/release-notes.sh <tag>)"`.

## Testing

Never test against the real setup: `enable` and `apply` rewrite the user's file associations.

- `scripts/sandbox.sh <command>` runs the checkout with every XDG dir in a throwaway sandbox. It
  reads the real bottles, writes nothing outside the sandbox and leaves the watcher off.
- `BO_DRY_RUN=1 scripts/sandbox.sh open <launcher> <file>` prints the launch command instead of
  starting the program. Launcher ids are in the sandbox's `state/bottles-opener/launchers`.
- `make check` after every change. New strings: `make pot`, then translate them in `po/de.po`.
