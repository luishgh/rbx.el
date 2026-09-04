# rbx.el

`rbx.el` brings the run and testset inspection workflow of the official
[`rbx` VS Code extension](https://rbx.rsalesc.dev/tools/vscode/) to Emacs 30.
It uses Magit Section for navigable trees, Transient for actions, Flymake for
compiler findings, and native read-only file and diff buffers for testcase
inspection.

The package follows the same terminal-first rule as the official extension:
**it never invokes `rbx`**. Run `rbx build` or `rbx run` yourself; Emacs watches
the package and renders the artifacts that land on disk.

## Features

- Live run view: solution → group → testcase, refreshed as `.eval` files land.
- Three distinct status channels: declared expectation, actual verdict, and
  whether the run met the declaration.
- Aggregate verdicts, scores, maximum time, and memory read from rbx's own
  `.rbx/runs/report.yml`; the Emacs package does not duplicate verdict logic.
- Compiler warnings and failures in the run view and through Flymake.
- Built testset browser with generator/copy provenance, validation status,
  artifact sizes, visualizations, and constraint coverage.
- Read-only input, expected answer, output, stderr, and log buffers.
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
  :hook ((c-mode c++-mode python-base-mode) . rbx-mode)
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

In a contest workspace, `M-x rbx-contest-view` (or `c` in the Transient) opens
a block per declared variant, each listing its problems by letter and color;
`RET` on a problem opens its run view. From a run view, `f` toggles following
whichever contest member most recently produced run artifacts, approximating
`rbx contest each run`'s progress since rbx keeps no on-disk record of which
problem is currently running.

Enable `rbx-mode` in solution buffers to bind `C-c r` and publish findings from
the most recent compile phase through Flymake. Diagnostics refresh when the rbx
artifacts change.

## Customization

- `rbx-testcase-layout`: split the initial testcase panes `below` or `beside`.
- `rbx-solution-label`: show solution paths as `full`, `trimmed`, or `basename`.
- `rbx-compilation-diagnostics`: enable or disable the Flymake backend.
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
tests, visualizers, statements, or packaging commands. Existing visualization
files can be opened from the testset view; generating new ones remains a
terminal operation. The testset and run surfaces are the primary supported
workflow for the initial release.

## Development

The project uses ERT and a test-first workflow. Run the complete local suite:

```sh
guix shell --pure -m manifest.scm -- make check
```

This runs ERT, byte compilation, Checkdoc, and package-lint in an isolated
environment. See [AGENTS.md](AGENTS.md) for architecture, TDD, and commit
conventions.

## License

MIT. See [LICENSE](LICENSE).
