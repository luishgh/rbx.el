# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and the
project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A time profile view (#12), `rbx-time-profile-view` (`T`), reads a limits
  profile, `.limits/<name>.yml`, as `rbx time` wrote it: each language
  group's limit and how it was reached, hand edits beside the estimate,
  the solutions the estimate measured and what checking the slow ones
  found, and the verdicts `rbx time --run-all` recorded at the limit, with
  any judged at an older limit flagged.  It refreshes when the profile
  changes.
- A partially correct testcase shows its share of the points, such as
  `74.06%`, on its run view row and info card (#9), and scores are coloured
  green when full, yellow when partial and red at zero, as `rbx run` does.
- The outcome `problem.rbx.yml` declares for a solution is shown in the mode
  line while you edit it (#8), before any run exists
  (`rbx-solution-declared-outcome`).  Aliases such as `ac/tle` and glob
  paths are resolved, the most specific entry wins, and an unreadable
  manifest shows nothing.
- Run view warnings that a result may be less trustworthy than it looks
  (#7): testcases a validator rejected under `--on-invalid=warn` are counted
  in the header, marked `⚠ invalid` and explained on the info card, with a
  quieter note when the run skipped validation; and a run that was
  interrupted or exited early says so, shows its unevaluated testcases as
  `never run`, and stops showing a running progress count.
- Small VS Code parity gaps (#6): a per-package `rbx-program` through
  `.dir-locals.el`; copy an artifact path (`y`) or reveal it in Dired (`j`);
  copy an interaction as an `.interaction` file (`C`); wall, checker and
  interactor times on the info card; what an ad-hoc run ran on in its
  heading; the full LaTeX log of a statement build (`L`); stress sessions
  whose rbx is gone read `stopped`; compare two solutions' stress outputs
  (`=`); the statement picker starts on the output built from the current
  buffer.
- Statement build errors are published through Flymake in the TeX files they
  name (`rbx-statement-diagnostics`), replacing the
  `rbx-show-statement-findings` buffer and its `E` binding.
- Optional evil-mode support (`rbx-evil.el`, opt in with
  `(with-eval-after-load 'evil (require 'rbx-evil))`): `rbx-view-mode` opens
  in evil's normal state and keeps its own bindings, with `g` freed for
  evil's motions and refresh moved to `g r`. `evil` is not a hard dependency.
- Left-fringe indicators per solution in the run view (tick, red triangle,
  or yellow warning), distinct from the existing inline match-marker glyph.
- Contest support: discovery and tolerant parsing of `contest.rbx.yml` and
  its `contest.<id>.rbx.yml` variant siblings, problem labeling by declared
  contest letter and color, division disambiguation when two contests share
  a letter, a dedicated contest view rendering one block per variant, and
  best-effort following of the contest problem most recently touched by
  `rbx contest each run`.
- A dedicated testcase info card (`m`) with the full, wrapped checker or
  validator message and test origin, for both run and built-test browsing.
- Actions to jump to a testcase's generator script line or copied-from
  source (`s`), and to open a testset testcase's validator source (`V`).
- A collapsible "Testset statistics" section in the testset view, with
  total and per-group testcase counts, input/output sizes, and a
  proportional bar per group.
- An action to open a testset testcase's answer visualization (`A`),
  finally surfacing `rbx-testset-visualization-output`.
- A visualization gallery view (`rbx-visualization-gallery`, key `G`),
  grouped like the testset browser, with inline image thumbnails and link
  lines for HTML visualizations.
- Statement variable hints: `rbx-mode` shows what each `\VAR{...}` reference
  in a declared statement resolves to, including filters, by calling the
  read-only `rbx vars`/`rbx vars --render` the same way the VS Code
  extension does — the one deliberate exception to this package never
  invoking rbx. New `rbx-statement-var-hints` and `rbx-program` settings.
- Login-shell `PATH` fallback for `rbx-yq-program`/`rbx-program`, matching
  the VS Code extension: a GUI Emacs's `PATH` does not necessarily match
  the user's shell. A total failure to resolve either executable is now
  reported once via `display-warning` instead of degrading silently.

### Changed

- Rename the project from `rbx-for-emacs` to `rbx.el`.
- Convert YAML artifacts to compact JSON with `yq` and parse them using
  Emacs's native JSON parser instead of `yaml.el`.

### Added

- A local `guix.scm` package definition for isolated builds and interactive
  smoke testing.

### Fixed

- A program that exits right away, such as a quick `--version` probe, could be
  reported as having failed to start, losing its output and exit code.  Its
  stderr could also pick up a stray `Process rbx-process stderr finished`
  line.
- Scores read as `rbx run` prints them against rbx 2.3.4, which writes them as
  floats: `[100/100]` and `[37.04/100]` rather than `[100.0/100]`.
- The `partially-correct` verdict and `PARTIALLY_CORRECT` expectation show as
  `PC` in yellow, rather than an unknown verdict.
- Refuse to start without mikefarah/yq instead of recursing: a wrong or
  missing `yq` made executable probes re-enter through timers and process
  sentinels until Lisp nesting was exhausted.  Views now fail with a
  `user-error` naming the offending `yq`, and `rbx-mode` stays off inside a
  package (warning once when enabled from a hook).  Synchronous probes no
  longer run timers or other sentinels while waiting.
- Cache unchanged parsed artifacts and defer testcase evaluation parsing until
  its collapsed run group is expanded, substantially reducing run-view latency.
- Route run-view verdict styling through Magit Section's font-lock face
  properties so semantic colours are actually displayed in section headings.
- Give run verdicts and expectations explicit VS Code-derived colours on clean
  or limited themes, including restrained mismatch and warning row washes.

## [0.1.0] - 2026-08-25

### Added

- Pure-reader discovery of single-problem and contest workspaces.
- Tolerant parsers for run skeletons, evaluations, aggregate reports, testset
  manifests, compiler findings, validation, coverage, and visualizations.
- Live Magit Section run and testset views with Transient actions.
- Read-only testcase panes and native output-versus-answer diffs.
- Flymake diagnostics for compiler warnings and failures.
- Custom preset `buildDir` resolution and debounced filesystem watching.
- ERT coverage, byte-compilation checks, Checkdoc, and contributor guidance.

[Unreleased]: https://github.com/luishgh/rbx.el/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/luishgh/rbx.el/releases/tag/v0.1.0
