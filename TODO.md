# TODO

Features present in the [rbx VS Code extension](rbx-vscode-features.md) that
are not yet implemented in `rbx.el`. Items that only make sense in a VS
Code/VSIX packaging context (sideloading, remote SSH/devcontainer install,
`rbx vscode install`) are out of scope for an Emacs package and are omitted.

## Contest support

- [x] Problem picker that behaves like a dropdown scoped to a contest, with
      problems named by **contest letter and color** rather than by relative
      path.
- [x] Auto-follow the currently running problem, mirroring
      `rbx contest each run` (best-effort, inferred from run-artifact
      activity since rbx keeps no on-disk marker of which problem is
      running).
- [x] Contest **variant** support: one block per variant with a variant ID
      heading (`rbx-contest-view`).
- [x] Distinct display for separate **divisions** within a contest.

## Testcase inspection

- [x] Dedicated testcase info card showing the checker's own message in full
      (wrapped, not truncated) (`rbx-show-testcase-info`, key `m`).
- [x] Test origin (generator call/script or copied-from) surfaced for **run**
      testcases, not just testset testcases (shown in the info card, via
      `rbx--testcase-provenance`).
- [x] "Visit source" action to jump to the generator script/line or the
      copied-from file for a testcase (`rbx-visit-testcase-source`, key `s`).
- [x] Action to open a testset testcase's **validator** source
      (`rbx-open-validator`, key `V`).

## Testset statistics

- [x] Dedicated Testset Statistics view: aggregate size and count
      information, group-by-group breakdown, and a visual representation
      (collapsible "Testset statistics" section in the testset view, with a
      proportional bar per group).

## Visualizations

- [x] Visualization **gallery** view for an entire group
      (`rbx-visualization-gallery`, key `G`).
- [x] Action to open the **answer** visualization
      (`rbx-open-answer-visualization`, key `A`).
- [x] Dedicated visualization gallery panel for packages that declare
      visualizers, with inline image thumbnails and link lines for HTML
      visualizations, grouped like the testset browser.

## Variables in statements

Implemented in `rbx-statement.el`, mirroring the VS Code extension's own
mechanism: it calls the read-only `rbx vars`/`rbx vars --render` rather than
reimplementing Jinja2, the one deliberate exception to this package's rule
of never invoking rbx (see `AGENTS.md`).

- [x] Inline/inlay expansion of `\VAR{...}` references with real-time values
      (overlay hints wired into `rbx-mode`).
- [x] Filter support: `sci`, `rsci`, and Jinja2 builtins — full fidelity,
      since `rbx vars --render` evaluates the pipeline, not a local
      reimplementation.
- [x] Test-group variable resolution, including named group access, group
      overrides, and shorthand/bracket notation, via live `rbx vars --json
      --groups` output (not `rbx-testset-group-vars`/`testset.yml`, which
      would require a prior `rbx build`).
- [x] Plain-text rendering of expressions (superscript digits, `×` for
      multiplication) — `--target text`, rendered by rbx itself.
- [x] Hint-placement rules: only for explicitly named groups; no hints for
      dynamic loops, undefined variables, problem/contest-scoped variables,
      or half-typed/typo'd pipelines — enforced structurally by the scanner
      grammar in `rbx-statement-scan-buffer`.
- [x] `rbx-statement-var-hints` custom variable (mirrors
      `rbx.statementVarHints`) to toggle the feature.

## Finding rbx / yq

- [x] Login-shell `PATH` fallback for GUI Emacs sessions where `yq` (or,
      since statement hints, `rbx` itself) isn't visible on the process
      `PATH` (`rbx-resolve-executable`, mirroring the VS Code extension's
      `rbx/executable.ts`).
- [x] Explicit, visible degradation message when `yq`/`rbx` is missing
      entirely, via a one-time `display-warning` (`rbx--warn-once`)
      instead of `rbx-read-yaml` silently returning nil. A conversion that
      fails on a specific, resolvable `yq` (as opposed to `yq` being
      entirely unavailable) still degrades silently, since that can be a
      transient artifact write in progress.

## Run view polish

- [ ] Actual gutter/fringe indicators (tick / red triangle / yellow warning)
      per solution, distinct from the inline match-marker glyphs
      (`rbx--match-marker`) already shown in the heading text.
