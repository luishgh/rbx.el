<!--
Model for the "VS Code parity" issue filed by the bump-rbx skill.
Title: VS Code parity: features from rbx <reviewed>..<target>
Replace every <placeholder>, repeat the feature block per proposed feature, and
delete this comment. Keep it concrete: someone should be able to start on a
feature from its block alone. Wrap code, paths and any @-prefixed text in
backticks so GitHub does not notify an unrelated account.
-->

## Summary

Reviewing the VS Code extension through rbx `<target>` found these features that
rbx.el does not have yet. They are tracked as `proposed` in
[`docs/vscode-parity.md`](https://github.com/luishgh/rbx.el/blob/main/docs/vscode-parity.md).

- [ ] <Feature name>
- [ ] <Feature name>

Upstream range: [`<reviewed>...<target>`](https://github.com/rsalesc/rbx/compare/<reviewed>...<target>)

Carried over from earlier reviews (`gap` rows): <Feature names, or delete this line.>

## Proposed features

### <Feature name>

**In the extension:** <What the user sees and does, in one or two sentences.>

**Evidence:** <Changelog entry and upstream PR (rsalesc/rbx#NNN); `vscode/src/...` files; `package.json` command, view or setting ids.>

**Proposal for rbx.el:** <The native Emacs shape: which view or Magit section changes, Transient entry or key binding, how files open.>

**Data source:** <The on-disk artifact it reads, and its path relative to the package. Note whether the layout belongs in `rbx-core.el` and how older rbx versions lacking it degrade.>

**Fit with project principles:** <Confirm it is pure reading: rbx.el does not invoke `rbx`. If the extension's version launches rbx, describe the reduced form proposed here. Preserve the separate declared/actual/matched channels if verdicts are involved.>

**Tests:**

- <Hermetic ERT test and fixture shape, written first.>
- <Integration coverage against a real rbx, if the default preset can exercise it.>

## Considered and not proposed

New changes in this range that won't be proposed, with the status recorded in the
parity file:

| Change | Status | Reason |
| --- | --- | --- |
| <Change> | <`mapped`, `adapted` or `discarded`> | <Already covered by `<command>`, or out of scope because ...> |

## Notes

<Dependencies between features, a suggested order, and open questions. Delete this section if empty.>
