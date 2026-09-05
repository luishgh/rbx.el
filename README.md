# rbx.el

`rbx.el` brings the run and testset inspection workflow of the official
[`rbx` VS Code extension](https://rbx.rsalesc.dev/tools/vscode/) to Emacs 30.
It uses Magit Section for navigable trees, Transient for actions, Flymake for
compiler findings, and native read-only file and diff buffers for testcase
inspection.

The package follows the same terminal-first rule as the official extension:
**it never invokes `rbx`**, with one deliberate, narrow exception. Run
`rbx build` or `rbx run` yourself; Emacs watches the package and renders the
artifacts that land on disk. The exception is statement variable hints: `rbx
vars` and `rbx vars --render` are read-only and idempotent by rbx's own
design, safe to call while a package is being edited, and the VS Code
extension calls them the same way.

## Features

- Live run view: solution → group → testcase, refreshed as `.eval` files land.
- Three distinct status channels: declared expectation, actual verdict, and
  whether the run met the declaration — the last shown both inline and as a
  left-fringe indicator (tick, red triangle, or yellow warning) per solution.
- Aggregate verdicts, scores, maximum time, and memory read from rbx's own
  `.rbx/runs/report.yml`; the Emacs package does not duplicate verdict logic.
- Compiler warnings and failures in the run view and through Flymake.
- Built testset browser with generator/copy provenance, validation status,
  artifact sizes, visualizations, and constraint coverage.
- Aggregate testset statistics: total and per-group testcase counts and
  input/output sizes, with a proportional bar per group.
- A visualization gallery, grouped like the testset browser, with inline
  image thumbnails and link lines for HTML visualizations; opens the input
  or answer visualization for any testcase from either view.
- Read-only input, expected answer, output, stderr, and log buffers.
- A dedicated testcase info card showing the full, wrapped checker or
  validator message and the test's origin (generator call, generator
  script, or copied-from source) for both run and built-test browsing.
- Jump straight to a testcase's generator script line or copied-from
  source, and to a testset testcase's validator source.
- Native unified diffs of solution output against the expected answer.
- Sticky output/stderr/log selection and persistent testcase windows: after the
  first split, your window arrangement is reused.
- Multi-problem discovery and selection for contest projects, naming problems
  by their declared contest letter and color, disambiguating divisions that
  share a letter, and a dedicated contest view listing every declared
  variant side by side (rbx never records which `-C` variant a terminal
  invocation used).
- Best-effort following of the contest problem most recently touched by
  `rbx contest each run`, inferred from run-artifact activity since rbx
  itself keeps no on-disk record of which problem is currently running.
- Statement variable hints: what each `\VAR{...}` reference in a declared
  statement resolves to, including filters (`sci`, `rsci`, and Jinja
  builtins), shown next to the reference and kept live as you edit or as
  `problem.rbx.yml` changes.
- Support for custom `buildDir` values from local rbx presets.
- Version-skew-tolerant artifact readers using `yq` and Emacs's native JSON
  parser, with correct generated artifact stems.

## Requirements

- Emacs 30.1 or newer (developed and tested on Emacs 30.2)
- Magit Section 4.1.0 or newer (tested with 4.6.0)
- Transient 0.7.5 or newer (tested with 0.13.5)
- yq 4.x (tested with 4.53.3)

The Emacs dependencies are available from GNU ELPA/nonGNU ELPA. All
dependencies, including `yq`, are declared in `manifest.scm` for Guix users.

## Installation

Until the package is published, clone this repository and use Emacs's built-in
VC package support:

```elisp
(package-vc-install '(rbx :url "https://github.com/luishgh/rbx.el"))
```

For local development, add the checkout to `load-path`:

```elisp
(add-to-list 'load-path "/path/to/rbx.el")
(require 'rbx)
```

With Guix, build and test the package in an isolated build container:

```sh
guix build -f guix.scm
```

To try the resulting package in a clean interactive Emacs session:

```sh
guix shell --pure -f guix.scm emacs -- emacs -Q
```

An example `use-package` configuration:

```elisp
(use-package rbx
  :bind (("C-c r" . rbx-dispatch))
  :hook ((c-mode c++-mode python-base-mode latex-mode LaTeX-mode) . rbx-mode)
  :custom
  (rbx-testcase-layout 'below)
  (rbx-solution-label 'trimmed))
```

## Usage

From a terminal in an rbx problem package:

```sh
rbx run
```

Then run `M-x rbx-dispatch` and choose the Run view, or invoke
`M-x rbx-run-view` directly. For artifacts produced by `rbx build`, open
`M-x rbx-testset-view`.

The view uses familiar Magit navigation:

| Key | Action |
| --- | --- |
| `n` / `p` | Move between sections |
| `TAB` | Expand or collapse a section |
| `RET` | Open the item at point |
| `g` | Refresh immediately |
| `?` | Open the rbx Transient |
| `q` | Close the view window |

On a testcase, `RET` opens the input and a second pane. For run testcases that
pane contains an output-versus-answer diff; for built tests it contains the
expected answer. The Transient can switch the second pane between output,
stderr, and the run log. The choice stays active while you inspect other tests.
`m` opens a dedicated info card with the testcase's origin and the full,
wrapped checker or validator message; `s` jumps to the generator script line
or copied-from source behind it; `V` opens a testset testcase's validator
source; `v`/`A` open a testset testcase's input/answer visualization.

`M-x rbx-visualization-gallery` (or `G` in the Transient) opens a gallery of
every group's visualizations for a package: an inline thumbnail for image
visualizations, or a link line for HTML ones. `RET` on an entry opens it
full-size.

In a contest workspace, `M-x rbx-contest-view` (or `c` in the Transient) opens
a block per declared variant, each listing its problems by letter and color;
`RET` on a problem opens its run view. From a run view, `f` toggles following
whichever contest member most recently produced run artifacts, approximating
`rbx contest each run`'s progress since rbx keeps no on-disk record of which
problem is currently running.

Enable `rbx-mode` in solution buffers to bind `C-c r` and publish findings from
the most recent compile phase through Flymake. Diagnostics refresh when the rbx
artifacts change.

Enable `rbx-mode` in a statement buffer (anything `problem.rbx.yml` declares
under `statements:`) to show what each `\VAR{...}` reference resolves to,
right after it, kept live as you edit or as `problem.rbx.yml` changes. Only a
reference rbx can answer for gets a hint — a bare package var, a loop-bound
group, an undefined name, or a half-typed filter pipeline simply shows
nothing, never a guess.

## Customization

- `rbx-testcase-layout`: split the initial testcase panes `below` or `beside`.
- `rbx-solution-label`: show solution paths as `full`, `trimmed`, or `basename`.
- `rbx-compilation-diagnostics`: enable or disable the Flymake backend.
- `rbx-statement-var-hints`: enable or disable `\VAR{...}` value hints.
- `rbx-program`: path to the `rbx` executable used for statement hints.
  Resolved against the process `PATH` and, failing that, a login shell
  (`$SHELL -lic "command -v rbx"`) — useful when Emacs was launched from a
  desktop icon rather than a terminal. A total failure to find it is
  reported once via `display-warning`, not silently.
- `rbx-yq-program`: path to the `yq` executable used to read YAML
  artifacts, resolved and reported the same way as `rbx-program`.
- `rbx-refresh-delay`: debounce interval for filesystem notifications.

Use `M-x customize-group RET rbx` to edit these settings interactively.

## Artifact contract

The reader centralizes the current rbx layout in `rbx-core.el`:

```text
<package>/problem.rbx.yml
<package>/.rbx/runs/skeleton.yml
<package>/.rbx/runs/report.yml
<package>/.rbx/runs/<solution>/<group>/<stem>.eval|.out|.err|.log
<package>/<buildDir>/testset.yml
<package>/<buildDir>/tests/<group>/<stem>.in|.out
```

The generated input basename—not merely the testcase index—determines
`<stem>`. This matters for subgroup-generated tests and is covered by ERT.

## Scope

The package observes existing artifacts. It does not run builds, runs, stress
tests, visualizers, or packaging commands. Existing visualization files can
be opened from the testset view; generating new ones remains a terminal
operation. The one exception is statement variable hints (see Features),
which call the read-only `rbx vars`/`rbx vars --render`. The testset and run
surfaces are the primary supported workflow for the initial release.

## Development

The project uses ERT and a test-first workflow. Run the complete local suite:

```sh
guix shell --pure -m manifest.scm -- make check
```

This runs ERT, byte compilation, Checkdoc, and package-lint in an isolated
environment. See [AGENTS.md](AGENTS.md) for architecture, TDD, and commit
conventions.

For integration testing against a real `rbx` (rather than fixture packages),
get a pinned copy from PyPI, hash-locked via `rbx-requirements.txt`:

```sh
guix shell --pure -m manifest.scm -- make rbx-venv
```

This creates `.venv-rbx` and installs the exact `rbx` release and dependency
versions `rbx-requirements.txt` pins; use `.venv-rbx/bin/rbx`. To bump the
pinned version, update the dependency in the throwaway `uv`-managed project
used to generate the lock, rerun `uv lock && uv export --no-dev
--no-emit-project -o rbx-requirements.txt`, and replace the file.

## License

MIT. See [LICENSE](LICENSE).
