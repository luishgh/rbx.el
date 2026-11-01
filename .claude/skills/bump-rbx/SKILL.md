---
name: bump-rbx
description: Bump the vendored rbx (the `rbx-cp` pin in rbx-requirements.txt) to a new release in rbx.el. Checks PyPI for a newer release, regenerates the hash-locked requirements, reads upstream's CHANGELOG.md, runs the integration suite and fixes drift, evaluates what changed in the VS Code extension, and files a GitHub issue proposing the features worth porting. Use whenever the user asks to bump, update or upgrade rbx or rbx-cp, refresh rbx-requirements.txt or .venv-rbx, asks whether a new rbx release is out, or wants to catch up with the upstream rbx VS Code extension.
---

# Bump the vendored rbx

`rbx-requirements.txt` pins the real `rbx` used by the integration suite. A bump
checks that rbx.el's readers still understand rbx's on-disk artifacts, and it is
also when we notice what the VS Code extension, the product rbx.el mirrors, has
gained.

An optional argument names a target version. Without one, target the latest
release on PyPI.

Project rules in `AGENTS.md` apply throughout. These matter most here:

- Every test run goes through `guix shell --pure -m manifest.scm --`.
- A missing program gets added to `manifest.scm`. Never drop `--pure` to work
  around it.
- Bug fixes are test-first.

## 1. Check that a release exists

The package is `rbx-cp` on PyPI. Upstream is `rsalesc/rbx`, whose tags are bare
versions (`2.3.4`) and which publishes no GitHub Releases, so `gh release` shows
nothing useful. PyPI is the source of truth because that is where we install
from.

```sh
grep -oP '^rbx-cp==\K\S+' rbx-requirements.txt
curl -fsS https://pypi.org/pypi/rbx-cp/json | python3 -I -c \
  "import json,sys; i=json.load(sys.stdin)['info']; print(i['version'], 'yanked:', i['yanked'], 'python:', i['requires_python'])"
```

If the pin is already at or past the target, say so and stop: no branch, no
issue. A named target must appear under `releases` in that JSON and not be
yanked. Call the old version `<pinned>` and the new one `<target>`.

## 2. Preflight and baseline

Stop and ask if the worktree is dirty. Check that `gh auth status` and `uv
--version` work; if the host has no `uv`, use `guix shell uv -- uv ...`. Then
branch with `git switch -c chore/bump-rbx-<target>`.

Record the suite's state on the *old* pin before changing anything:

```sh
guix shell --pure -m manifest.scm -- make check-integration
```

Guix channel updates can break this suite on their own, so without a baseline a
new toolchain failure looks like rbx drift. Note every failure and every skip.

## 3. Bump the pin

Regenerate the lock in a throwaway `uv` project outside the repo. The lock is
the only artifact worth keeping. Use the session scratchpad, or `mktemp -d`.

```sh
guix shell --pure -m manifest.scm -- python3 --version   # use its major.minor below
cd <scratch>/lock
uv init --bare --no-workspace --python <major.minor>
uv add --no-sync 'rbx-cp==<target>'
uv export --no-dev --no-emit-project -o rbx-requirements.txt
cp rbx-requirements.txt <repo>/rbx-requirements.txt
```

Transitive dependencies move too, which is expected. Skim for major jumps with
`git diff -U0 rbx-requirements.txt | grep -E '^[-+][a-zA-Z0-9_.-]+=='`.

`make` rebuilds `.venv-rbx` because the requirements file is now newer. Confirm
the result:

```sh
guix shell --pure -m manifest.scm -- make rbx-venv
.venv-rbx/bin/rbx --version
```

## 4. Read the changelog

Clone upstream without blobs into the scratchpad. It stays cheap, and every
later comparison can use it. Only read from this clone (`git show`, `git diff`);
never run anything from it.

```sh
git clone -q --filter=blob:none --no-checkout https://github.com/rsalesc/rbx.git <scratch>/rbx-upstream
git -C <scratch>/rbx-upstream show <target>:CHANGELOG.md \
  | awk -v from=<pinned> '/^## /{ if ($2==from) exit; p=1 } p'
```

This prints every release in the range, including skipped ones. Note anything
that could touch the integration contract:

- `.rbx/` or build layout
- `report.yml`, testset, or stress and statement artifacts
- manifest schema
- verdict, outcome or score values
- `rbx vars` output

## 5. Run the integration tests

```sh
guix shell --pure -m manifest.scm -- make check-integration
```

Compare the result with the baseline, skips included. A test that skips rather
than fails has stopped checking anything, so explain each new skip. Tests skip
when `pdflatex` or an `rbx` feature is missing, for example.

## 6. Fix failures

Fix the cause. These tests exist to detect drift, so loosening an assertion or
adding a `skip-unless` just to get green defeats their purpose.

- **rbx's artifacts changed:** add or update a hermetic fixture in the ERT suite
  that reproduces the new shape, watch it fail, then fix the reader. Keep layout
  knowledge centralized in `rbx-core.el` and keep parsing tolerant, because users
  may run older or newer rbx than we pin.
- **The test assumed something rbx is free to change:** relax that test only if
  the assumption was never part of the contract.
- **Missing program or TeX package:** add it to `manifest.scm`, and to `guix.scm`
  if the package itself needs it.
- **Already failing at baseline:** report it separately, and don't let it mask
  anything new.

Green doesn't prove full compatibility. The suite scaffolds the `default` preset,
so a new value that only appears with, say, points scoring never reaches it.
Compare `vscode/src/rbx/rbxEnums.json`, `model.ts`, `manifest.ts` and `outcome.ts`
across the range: they are upstream's own reading of these artifacts. Handle new
values the same test-first way.  In particular, `rbx--outcome-aliases` in
`rbx-model.el` mirrors the outcome aliases in `rbxEnums.json` (and rbx's
`ExpectedOutcome`); update it when those change.

If a failure can't be resolved, stop here and report it, leaving the work on the
branch uncommitted. A feature proposal against a bump that doesn't land is
premature.

## 7. Evaluate the VS Code extension

[`docs/vscode-parity.md`](../../../docs/vscode-parity.md) records what rbx.el
decided about every extension feature, and is the baseline for this review. Its
"Reviewed through" line says where to start, which is normally `<pinned>`:

```sh
grep -oP 'Reviewed through rbx \K\d+(\.\d+)*' docs/vscode-parity.md
```

Call that version `<reviewed>`.

The changelog is not enough on its own. Only entries scoped `vscode` are
explicitly about the extension, yet other entries change it too. For example,
2.3.4's `scoring` and `testset` work edits `vscode/src/rbx/` with no `vscode`
entry. Read the source diff as well, using the clone since GitHub's compare API
caps out at 300 files:

```sh
git -C <scratch>/rbx-upstream diff --stat <reviewed> <target> -- vscode docs/tools/vscode.md
git -C <scratch>/rbx-upstream diff <reviewed> <target> -- vscode/package.json docs/tools/vscode.md
git -C <scratch>/rbx-upstream log --oneline <reviewed>..<target> -- vscode
```

The `contributes` section of `package.json` (commands, views, settings) is the
quickest signal. Upstream's docs lag behind it: at 2.3.2 they don't mention the
Assets view at all. Then read the non-test files under `vscode/src/`, which is
where display-only changes show up. Ignore lockfile churn and version bumps.

Give each user-visible change a status, using the definitions in the parity file:

- **`mapped` or `adapted`:** rbx.el already covers it. Check the code before saying
  so, not just the docs.
- **`proposed`:** new behavior that fits rbx.el and that it doesn't have. It goes
  into the issue in step 8.
- **`discarded`:** say why. Typical reasons are VSIX packaging or install concerns,
  or anything that needs rbx.el to invoke `rbx`.

The package is a pure reader, and the `rbx vars` exception does not extend to
anything else. A feature that launches rbx can often still be proposed in reduced
form, showing the artifacts a terminal run leaves behind.

Also re-check existing rows the range touches. An `adapted` or `discarded` row can
become viable when upstream starts writing a new artifact, so the decision may
change. A `mapped` row can stop being true when the behavior changes.

Features that exist only in the CLI are not candidates unless the extension
surfaces them.

## 8. File the proposal issue

Propose the new features from step 7 together with any rows still marked `gap`.
A `gap` row is a feature we already found missing but never proposed, so this
stops it from being forgotten. If there is nothing to propose, skip this step and
say so in the report. An empty issue is just noise.

Rows marked `proposed` or `discarded` are already decided, so don't propose them
again. Check for an existing issue too, including closed ones:

```sh
gh issue list --state all --search '"VS Code parity" in:title'
```

Fill in [reference/issue-template.md](reference/issue-template.md), write the body
to the scratchpad, and create one issue for the whole batch. If an open issue
already covers the range, update it rather than filing a duplicate.

```sh
gh issue create --repo luishgh/rbx.el \
  --title 'VS Code parity: features from rbx <reviewed>..<target>' \
  --label enhancement \
  --body-file <scratch>/issue.md
```

The branch isn't pushed yet, so link to upstream tags and PRs rather than local
commits.

## 9. Update the project docs

- `docs/vscode-parity.md`:
  - Add a row for each new feature.
  - Change the rows you re-checked.
  - Set the proposed rows and swept `gap` rows to `proposed`, with the issue link.
  - Set "Reviewed through" to `<target>`, even if nothing else changed, so the next
    bump doesn't review this range again.
- `CHANGELOG.md`: under `[Unreleased]`, describe user-visible fixes, plus the new
  pin if it changes what users can rely on.
- `README.md`: change it only if test prerequisites or the bump procedure changed.
  Keep its bump instructions in step with step 3.

## 10. Verify and commit

```sh
guix shell --pure -m manifest.scm -- make check
```

If `guix.scm` or the package's dependencies changed, also run `guix build -f
guix.scm`. Keep the manifest and `guix.scm` synchronized if `yq` or another shared
dependency moved.

Commit on the branch in focused Conventional Commits, with `fix:` commits for
reader changes and `chore: bump vendored rbx to <target>` for the pin plus docs.
Leave the worktree clean. Don't push or open a PR unless the user asks.

## 11. Report

Finish with a short summary:

- the version range, and notable transitive dependency jumps
- contract-relevant changelog items
- integration results against the baseline: failures fixed, remaining skips
- what changed in the extension, by status, with the issue URL
- the branch name and commits, and that nothing was pushed
