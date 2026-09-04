# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and the
project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

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

### Changed

- Rename the project from `rbx-for-emacs` to `rbx.el`.
- Convert YAML artifacts to compact JSON with `yq` and parse them using
  Emacs's native JSON parser instead of `yaml.el`.

### Added

- A local `guix.scm` package definition for isolated builds and interactive
  smoke testing.

### Fixed

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
