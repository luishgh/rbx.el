# Project guidance

This repository implements an Emacs 30 package inspired by the official
[`rbx` VS Code extension](https://rbx.rsalesc.dev/tools/vscode/).

## Product principles

- Keep execution terminal-first.  The package is a pure reader: never invoke
  `rbx`, because even read-looking CLI invocations can mutate or invalidate its
  cache.
- Treat `rbx`'s on-disk artifacts as the integration contract.  Keep layout
  knowledge centralized and parse version-skewed YAML tolerantly.
- Preserve the extension's separate channels for declared expectation, actual
  verdict, and whether the two matched.  Do not reimplement verdict aggregation;
  read it from `.rbx/runs/report.yml`.
- Prefer native, modern Emacs UI: Magit Section for hierarchical views,
  Transient for commands, native buffers and `ediff`/diff facilities for files.
- Generated artifacts are read-only.  Reuse user-arranged windows after their
  initial layout whenever practical.
- Support Emacs 30.1 and newer.  Use lexical binding, namespaced symbols,
  `defgroup`/`defcustom`, autoload cookies, and package-lint-friendly headers.

## Development workflow

- Use ERT and test-driven development: add or change a failing test first, run
  it, implement only enough behavior to pass it, then refactor while green.
- Keep tests hermetic.  Create fixture packages under temporary directories;
  never require an installed `rbx` executable.
- Run `guix shell --pure -m manifest.scm -- make check` before every commit.
  This includes ERT, byte compilation, Checkdoc, and package-lint in an
  isolated environment.
- Keep `guix.scm` buildable after packaging or dependency changes.  Its Emacs
  build system runs `make check`, so validate it with `guix build -f guix.scm`.
- Use Conventional Commits such as `feat:`, `fix:`, `test:`, `docs:`, and
  `chore:`.  Keep commits focused and leave the worktree clean.
- Do not commit generated `.elc` or autoload files.
