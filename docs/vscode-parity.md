# VS Code extension parity

What rbx.el decided about each feature of the
[rbx VS Code extension](https://rbx.rsalesc.dev/tools/vscode/), the product it
mirrors.

**Reviewed through rbx 2.3.4.** The next review starts from this version.

## How to read and maintain this

| Status | Meaning | The last column holds |
| --- | --- | --- |
| `mapped` | Works as in the extension, in native Emacs form | Command, key or setting |
| `adapted` | Deliberately different, usually because of the pure-reader rule | What we do instead, and why |
| `gap` | Fits rbx.el and is missing, with no proposal filed yet | Notes for the proposal |
| `proposed` | Accepted as work, tracked in an issue | The issue link |
| `discarded` | Won't be implemented | The reason |

- Issues hold design and progress. This file only holds the outcome.
- Keep one row per feature. Finer detail belongs in the code, tests or issue.
- Update it during an rbx bump (see the `bump-rbx` skill), and in the change that
  closes a `proposed` issue.
- `D1` below stands for: *Execution stays in the terminal; rbx.el never invokes
  `rbx`, with `rbx vars` as the only exception (`AGENTS.md`).*

## Run view

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Live solution → group → testcase tree | `mapped` | `rbx-run-view` (`r`), refreshed by file watchers |
| Declared, actual and match shown as separate channels | `mapped` | Coloured name, verdict and match marker |
| Gutter tick, red triangle, yellow warning | `mapped` | Left-fringe indicators |
| Verdict, points, max time and memory per solution and group | `mapped` | Read from `.rbx/runs/report.yml` |
| Partially correct verdict and expectation | `mapped` | `PC` in yellow, in both channels |
| Fractional scores | `mapped` | Printed to the cent, as `rbx run` does |
| Percentage on a partially correct testcase | `proposed` | [#9](https://github.com/luishgh/rbx.el/issues/9) |
| Score coloured by how much it earned | `proposed` | [#9](https://github.com/luishgh/rbx.el/issues/9) |
| Progress while running (`12/40`) | `mapped` | Run view row summary |
| Limits per language and limits profile in the header | `mapped` | Run view header |
| `limits look untuned` notice | `mapped` | Run view header |
| `>2000 ms` for runs stopped at the expanded limit | `mapped` | Testcase rows |
| Hover a time to see its limit | `mapped` | `help-echo` on times and memory |
| Sanitizer warnings | `mapped` | Run view markers and `sanitized` heading |
| Collapse and expand all | `mapped` | `rbx-collapse-all` (`z M`), `rbx-expand-all` (`z R`) |
| Solution label setting (`rbx.solutionLabel`) | `mapped` | `rbx-solution-label` |
| Filter box over the run tree | `discarded` | Too complex for the benefit; re-running `rbx` on a subset of solutions covers most of the need |
| Testcases-as-tiles layout | `discarded` | Magit sections are line-based, so a grid needs its own navigation and context |
| Flag testcases that failed validation (`--on-invalid=warn`) | `proposed` | [#7](https://github.com/luishgh/rbx.el/issues/7) |
| Notice when a run was interrupted or ended early | `proposed` | [#7](https://github.com/luishgh/rbx.el/issues/7) |
| Notification when a dispatched run passed invalid tests | `discarded` | Only fires for runs the extension started (D1); the `gap` above covers terminal runs |

## Contests

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Problem picker named by contest letter and colour | `adapted` | `rbx-select-package` (`p`) with `completing-read`, not a dropdown |
| Follow the running problem | `adapted` | `rbx-toggle-contest-follow` (`f`), inferred from artifact activity because rbx records no marker |
| One block per variant, with heading | `mapped` | `rbx-contest-view` (`c`) |
| Divisions kept apart when letters collide | `mapped` | Problem labels and contest view |

## Testcases

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Two panes: input plus output diffed against answer | `mapped` | `rbx-open-testcase`, `RET` |
| Reuse panes wherever the user moved them | `mapped` | Persistent testcase windows |
| Initial layout setting (`rbx.testcaseLayout`) | `mapped` | `rbx-testcase-layout` |
| Sticky `out` / `err` / `log` channel | `mapped` | `rbx-show-output` (`1`), `rbx-show-stderr` (`2`), `rbx-show-log` (`3`) |
| Interaction transcript, interactor stderr and log, checker stderr | `mapped` | `4`–`7`, with margin labels on the transcript |
| Native diff of output against answer | `adapted` | `rbx-diff-output` (`d`) in a `diff-mode` buffer, since VS Code's diff isn't available |
| Open solution, input, output, answer, stderr | `mapped` | `rbx-open-solution`, `i`, `o`, `a`, `2` |
| Card: checker message in full, wrapped | `mapped` | `rbx-show-testcase-info` (`m`) |
| Card: test origin, linking to real files | `mapped` | `m`, then `rbx-visit-testcase-source` (`s`) |
| Card: wall, checker and interactor times | `proposed` | [#6](https://github.com/luishgh/rbx.el/issues/6) |
| Copy interaction as `.interaction` | `proposed` | [#6](https://github.com/luishgh/rbx.el/issues/6) |
| Copy paths and reveal in the file browser | `mapped` | `rbx-copy-path` (`y`) and `rbx-reveal-in-dired` (`j`) in the dispatch; a prefix argument picks the artifact |

## Compilation findings

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Findings panel with one row per solution, badged by severity | `adapted` | Compilation section inside the run view, not a separate panel |
| Warning rows jumping to the source line | `mapped` | `rbx-open-warning` |
| Verbatim compiler output for failures | `mapped` | `rbx-open-compilation-log` |
| Problems panel diagnostics (`rbx.compilationDiagnostics`) | `mapped` | Flymake via `rbx-compilation-diagnostics` |

## Testset

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Tests view: groups, testcases, origins | `mapped` | `rbx-testset-view` (`t`) |
| Open input and answer, card names validator and generator | `mapped` | `RET`, `m`, `rbx-open-validator` (`V`) |
| Constraint coverage | `adapted` | Section in the testset view, not a side panel |
| Testset stats by group | `adapted` | Section in the testset view, with a proportional bar per group |
| Filter box over the tests tree | `discarded` | Same as the run view filter |

## Visualizations

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Open input and answer pictures | `mapped` | `rbx-open-visualization` (`v`), `rbx-open-answer-visualization` (`A`) |
| Gallery of a whole group | `mapped` | `rbx-visualization-gallery` (`G`) |
| HTML visualizations | `adapted` | `browse-url-of-file` opens the system browser, as Emacs has no embedded equivalent |
| Draw a missing visualization on demand | `discarded` | Calls `rbx` (D1); run `rbx build --visualize` |
| Visualize a solution's output | `discarded` | Calls `rbx` (D1); use `rbx ui` |

## Testplans and promotion

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Generate, Validate, Run lenses over testplan statements (`rbx.testplanCodeLens`) | `discarded` | Each invokes `rbx` (D1) |
| Promote a test, input or stress finding, with proposal diffs | `discarded` | Invokes `rbx` and edits package files; generated views stay read-only (D1) |

## Ad-hoc runs

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Results of `rbx irun` in the run view layout | `mapped` | `rbx-adhoc-run-view` (`I`) |
| Toggle between last run and ad-hoc run, following the newest | `adapted` | Two separate views; no automatic switch |
| Hover shows what the ad-hoc run ran on | `proposed` | [#6](https://github.com/luishgh/rbx.el/issues/6) |
| Start `irun` from a testcase, input or generator call | `discarded` | Starts `rbx` (D1) |

## Stress testing

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Session state, executed count, findings so far | `mapped` | `rbx-stress-view` (`S`) |
| Finding row: generator call, verdict per solution | `mapped` | Finding and solution sections |
| Open input, answer, a solution's output and stderr | `mapped` | `i`, `a`, `o`, `2` |
| Copy generator call | `mapped` | `rbx-copy-stress-generator` (`w`) |
| Compare the outputs of two solutions | `proposed` | [#6](https://github.com/luishgh/rbx.el/issues/6) |
| Detect a session left `running` with no live rbx (`stale`) | `proposed` | [#6](https://github.com/luishgh/rbx.el/issues/6) |
| Declared stress list, launcher form, start and stop | `discarded` | Starts or stops `rbx` (D1) |

## Statements

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| `\VAR{...}` hints, filters, group variables, placement rules | `mapped` | `rbx-mode` overlays via `rbx vars` (the allowed exception); `rbx-statement-var-hints` |
| Statement source list resolved by `rbx statements ls` | `adapted` | Reads the manifest instead (D1); entries using `extends` with no `file` get no hints; a `{lang}` template in `file` is matched against files on disk, as upstream does |
| PDF preview reloading on each build | `mapped` | `rbx-preview-statement` (`P`) with auto-revert |
| Picker across statements, tutorials, variants | `adapted` | `completing-read` over the build report, no in-panel picker |
| Picker starts on the source being edited | `proposed` | [#6](https://github.com/luishgh/rbx.el/issues/6) |
| Picker follows as you switch sources | `discarded` | Needs a window-change hook that would fight user-arranged windows |
| Build errors on the source line (`rbx.statementDiagnostics`) | `mapped` | Flymake via `rbx-statement-diagnostics` |
| Banner listing failures, with a link to the full LaTeX log | `proposed` | [#6](https://github.com/luishgh/rbx.el/issues/6) |
| Build button and `rbx.statements.buildOnSave` | `discarded` | Starts `rbx` (D1) |

## Solution and file annotations

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Declared outcome while editing a solution (`rbx.solutionCodeLens`, `rbx.solutionStatus`) | `proposed` | [#8](https://github.com/luishgh/rbx.el/issues/8) |
| Explorer and tab badges (`rbx.decorateExplorer`) | `discarded` | The declared outcome in the solution buffer gives most of the value, and tabs have no equivalent |
| Assets view, across problems and by problem | `discarded` | Needs reimplementing rbx's asset resolution, or a second exception to the no-invoke rule for `rbx assets --json` |

## Dispatch and installation

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| Run, build, rerun, contest run buttons (`rbx.dispatch.enabled`, `rbx.run.extraArgs`) | `discarded` | Start `rbx` (D1) |
| `rbx vscode install`, VSIX sideloading, remote extension host | `discarded` | VS Code packaging only |

## Finding rbx and yq

| Extension feature | Status | rbx.el |
| --- | --- | --- |
| `PATH` then login-shell lookup | `mapped` | `rbx-resolve-executable` |
| Manual override (`rbx.executable`) | `mapped` | `rbx-program`, `rbx-yq-program` |
| Views keep working without `rbx` | `mapped` | Only statement hints need it; `yq` stays required and its absence is reported |
| Per-folder override | `mapped` | `rbx-program` in `.dir-locals.el`; Emacs prompts for unsafe values |
