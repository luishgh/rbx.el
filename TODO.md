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

- [ ] Visualization **gallery** view for an entire group (currently only a
      single testcase's input visualization can be opened via
      `rbx-open-visualization`).
- [ ] Action to open the **answer** visualization (`rbx-testset-visualization-output`
      is parsed but never surfaced — only `-input` is opened).
- [ ] Dedicated visualization gallery panel for packages that declare
      visualizers, independent of constraint-coverage visualization (already
      done) and single-testcase image opening (already done).

## Variables in statements

Entirely unimplemented — no code currently touches `.tex` statement files.

- [ ] Inline/inlay expansion of `\VAR{...}` references with real-time values.
- [ ] Filter support: `sci`, `rsci`, and Jinja2 builtins (`upper`,
      `round(2)`, etc.).
- [ ] Test-group variable resolution, including named group access, group
      overrides, and shorthand/bracket notation. Note `rbx-testset-group-vars`
      is already parsed from `testset.yml` but nothing consumes it.
- [ ] Plain-text rendering of expressions (superscript digits, `×` for
      multiplication).
- [ ] Hint-placement rules: only for explicitly named groups; no hints for
      dynamic loops, undefined variables, problem/contest-scoped variables,
      or half-typed/typo'd pipelines.
- [ ] `rbx-statement-var-hints` custom variable (mirrors
      `rbx.statementVarHints`) to toggle the feature.

## Finding rbx / yq

- [ ] Login-shell `PATH` fallback for GUI Emacs sessions where `yq` isn't
      visible on the process `PATH` (no `exec-path-from-shell`-style
      resolution around `rbx-yq-program`).
- [ ] Explicit, visible degradation message when `yq` is missing or fails,
      rather than `rbx-read-yaml` silently returning nil and the view
      reporting "No run artifacts yet" even though artifacts exist.

## Run view polish

- [ ] Actual gutter/fringe indicators (tick / red triangle / yellow warning)
      per solution, distinct from the inline match-marker glyphs
      (`rbx--match-marker`) already shown in the heading text.
