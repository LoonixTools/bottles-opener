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

## Testing

Never test against the real setup: `enable` and `apply` rewrite the user's file associations.

- `scripts/sandbox.sh <command>` runs the checkout with every XDG dir in a throwaway sandbox. It
  reads the real bottles, writes nothing outside the sandbox and leaves the watcher off.
- `BO_DRY_RUN=1 scripts/sandbox.sh open <launcher> <file>` prints the launch command instead of
  starting the program. Launcher ids are in the sandbox's `state/bottles-opener/launchers`.
- `make check` after every change. New strings: `make pot`, then translate them in `po/de.po`.
