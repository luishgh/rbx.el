# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and the
project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

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

[Unreleased]: https://github.com/luishgh/rbx-for-emacs/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/luishgh/rbx-for-emacs/releases/tag/v0.1.0
