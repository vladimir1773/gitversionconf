# GitVersion configuration

This repository uses GitVersion to calculate versions for a CD deploy-repo
branching model with three relevant branch families:

- `main` / `master`
- `hotfix/*`
- `feature/*`

`release/*` and `develop` are intentionally out of scope for this repository.

## What GitVersion does here

GitVersion calculates the semantic version and branch-specific pre-release
label for the authoritative pipeline branches. It does not enforce deployment
approvals, protected tags, production usage, or environment promotion order.
Those rules must be implemented in the Git host and CI/CD pipeline.

Feature branches are different: developers may create their own tags there for
test or x0 deployments. Those feature tags are not authoritative. Once a
feature branch is merged into `main` / `master`, GitVersion should calculate
the next protected tag from the merged commit history on `main` / `master`.

The expected protected main/master production tag format is:

```text
<MajorMinorPatch>
```

Example:

```text
0.0.1
```

Hotfix builds still use a pre-release label while the hotfix branch is open:

```text
0.0.1-hotfix-urgent.1
0.0.1-hotfix-urgent.2
0.0.1-hotfix-urgent.3
```

The protected hotfix deployment tag should be created by the pipeline from
`FullSemVer`, for example `0.0.1-hotfix-urgent.1`.

## Top-level settings

### `workflow: GitHubFlow/v1`

GitHubFlow is used because this deploy repo has a simple mainline model:
changes flow through `main`, with temporary `feature/*` and `hotfix/*`
branches. Long-lived `develop` and `release/*` branches are not part of the
model.

### `mode: ContinuousDelivery`

Continuous Delivery mode keeps producing predictable versions from each branch
until an explicit tag exists.

For protected main/master tags, use the `MajorMinorPatch` variable. For
example:

```text
0.0.1
```

The pipeline can then create the protected tag:

```text
0.0.1
```

### `tag-prefix`

```yaml
tag-prefix: '[vV]?(?=\d+\.\d+\.\d+$)'
```

GitVersion should only treat stable protected main/master tags as version
sources:

```text
0.0.1
v0.0.1
```

The `v` prefix is optional.

This is intentionally stricter than the default `tag-prefix: '[vV]?'`.
Developers may tag feature branches however they want, and those tags may be
merged into `main` / `master` as part of the Git graph. They must not take over
the next production version calculation.

Hotfix deployment tags such as `0.0.1-hotfix-urgent.1` are also ignored as
version sources. The stable main/master tag is the authoritative version
source.

### `semantic-version-format: Strict`

Strict SemVer parsing is used so invalid or ambiguous version tags fail early
instead of becoming part of the version history accidentally.

### `commit-message-incrementing: Enabled`

Commit messages may request explicit version bumps:

```text
+semver: patch
+semver: minor
+semver: major
+semver: none
```

Patch is the default branch increment. These messages allow intentional patch,
minor, and major bumps without changing the GitVersion config.

For feature work, the important part is the merged history: if a feature branch
contains `+semver: minor` or `+semver: major` and is merged into
`main` / `master` without losing that commit message, GitVersion can use that
history when calculating the next protected tag on `main` / `master`.

## Branches

### `main`

```yaml
main:
  regex: ^(?:main|master)$
  label: ''
  mode: ContinuousDelivery
  increment: Patch
```

`main` / `master` represents the blue main pipeline in the diagram.

The label is intentionally empty. Main/master production tags should be stable
SemVer tags:

```text
0.0.1
```

On an untagged main/master commit, `FullSemVer` may contain a build counter
such as `0.1.1-3`. The production tag should still use `MajorMinorPatch`, for
example `0.1.1`.

`increment: Patch` is the default increment for normal mainline movement. The
larger jumps shown in the diagram are handled explicitly through commit-message
incrementing in the history that lands on `main` / `master`:

```text
0.0.1 -> 0.1.0 -> 1.0.0 -> 1.1.0 -> 2.0.0
```

Patch is the safe default. Minor and major jumps should be requested explicitly
through commit messages such as `+semver: minor` or `+semver: major`.

### `prevent-increment`

```yaml
prevent-increment:
  of-merged-branch: false
  when-current-commit-tagged: true
```

`of-merged-branch: false` is important for this flow. It allows version bump
signals from a merged feature branch to influence the next `main` / `master`
calculation.

`when-current-commit-tagged: true` avoids an extra bump when the current
commit already has the protected pipeline tag.

### `source-branches`

```yaml
source-branches:
  - feature
  - hotfix
```

This does not mean GitVersion checks out or uses those branches as a fixed
base. It means GitVersion may interpret `feature/*` and `hotfix/*` branches as
valid sources that can be merged into `main` / `master`.

### `hotfix/*`

```yaml
hotfix:
  regex: ^hotfix(es)?[/-](?<BranchName>.+)
  label: hotfix-{BranchName}
  mode: ContinuousDelivery
  increment: None
```

`hotfix/*` represents the green hotfix pipeline in the diagram.

The label includes the hotfix branch name:

```text
hotfix-{BranchName}
```

That means GitVersion can calculate:

```text
0.0.1-hotfix-urgent.1
0.0.1-hotfix-urgent.2
0.0.1-hotfix-urgent.3
```

`increment: None` is intentional here. A hotfix branch should copy the
`MajorMinorPatch` from its source on `main` / `master` and append a hotfix
label that contains the branch name. The counter at the end represents the
hotfix branch iterations.

Including the branch name avoids collisions when two hotfix branches are cut
from the same main/master version. For example:

```text
hotfix/urgent    -> 0.0.1-hotfix-urgent.1
hotfix/login-fix -> 0.0.1-hotfix-login-fix.1
```

The pipeline should create the protected hotfix deployment tag from
`FullSemVer`:

```text
0.0.1-hotfix-urgent.1
```

`source-branches` is restricted to `main`:

```yaml
source-branches:
  - main
```

This documents the intended flow: hotfix branches are created from `main` /
`master`.

The actual next stable SemVer is calculated after the hotfix branch is merged
back into `main` / `master`. At that point, the hotfix commits are part of the
main/master history and the normal main/master increment rules apply.

The additional approval required for production hotfix deployment is not a
GitVersion concern. It must be enforced by the deployment pipeline or
environment protection rules.

### `feature/*`

```yaml
feature:
  regex: ^features?[/-](?<BranchName>.+)
  label: '{BranchName}'
  mode: ManualDeployment
  increment: Inherit
```

`feature/*` represents the orange feature pipeline in the diagram.

The label is the branch name. For example:

```text
feature/d0-u1-demo
```

can produce:

```text
0.0.1-d0-u1-demo.1+1
```

`ManualDeployment` is used because feature deployments are explicitly
self-created or triggered when needed. They are not treated like the protected
main and hotfix CD paths.

Feature branch tags are intentionally non-authoritative. Developers may tag
feature branches for their own deployment needs, but protected version tags are
calculated after the feature branch lands on `main` / `master`.

`increment: Inherit` keeps feature branches from defining a separate release
policy. Version bump intent should be carried by commit messages that survive
the merge:

```text
+semver: patch
+semver: minor
+semver: major
```

### `pull-request`

Pull request branches receive a `PullRequest{Number}` label. They are included
so CI validation builds have deterministic versions without being confused
with protected release or hotfix tags.

Example:

```text
0.0.1-PullRequest42.1
```

### `release/*` and `develop`

```yaml
release:
  regex: ^$

develop:
  regex: ^$
```

These branches are intentionally disabled for this deploy-repo model.

`regex: ^$` only matches an empty branch name, so normal branches such as
`release/1.0.0` or `develop` will not match these branch configurations.

This mirrors the diagram where `Release` and `Develop` are marked
out-of-scope.

### `unknown`

The `unknown` branch configuration is a fallback for branches that do not match
the explicit patterns above.

It uses:

```yaml
mode: ManualDeployment
increment: Inherit
label: '{BranchName}'
```

That keeps unexpected branches from looking like protected main/master or
hotfix builds.

## What must be enforced outside GitVersion

The following rules are part of the concept, but not enforceable by
GitVersion.yml:

- protected tag creation
- tag naming restrictions
- production deployment approval
- hotfix additional approval
- environment order such as `d0/1 -> u0/u1 -> t0/t1 -> p0`
- feature-only x0 deployment
- ensuring feature tags do not match protected production tag patterns
- blocking `release/*` and `develop` in CI

Recommended protected tag patterns:

```text
^v?\d+\.\d+\.\d+$
^v?\d+\.\d+\.\d+-hotfix-[0-9A-Za-z-]+\.\d+$
```

These should be implemented in the Git host and CI/CD pipeline.

## Manual Test Guide

The following commands validate the branching model without a CI/CD pipeline.
They create a temporary repository, copy this `GitVersion.yml`, and exercise the
main/master, hotfix, and feature flows.

Run the guide from this repository:

```bash
cd "/Users/vladimir/Documents/New project 2/gitversionconf"
```

### Setup

```bash
TEST_DIR="$(mktemp -d /tmp/gitversion-manual-test.XXXXXX)"
cp GitVersion.yml "$TEST_DIR/GitVersion.yml"
cd "$TEST_DIR"

git init -b main
git config user.name "Manual Test"
git config user.email "manual@test.local"

touch README.md
git add README.md GitVersion.yml
git commit -m "initial"
```

### Case 1: Main Starts Stable

```bash
gitversion /showvariable MajorMinorPatch
gitversion /showvariable FullSemVer
```

Expected:

```text
0.0.1
0.0.1
```

Create an authoritative stable main/master tag:

```bash
git tag 0.1.0
```

### Case 2: Hotfix Copies Main SemVer And Counts Iterations

```bash
git switch -c hotfix/urgent

gitversion /showvariable MajorMinorPatch
gitversion /showvariable FullSemVer
```

Directly on the tagged source commit, `FullSemVer` can still be:

```text
0.1.0
```

Create the first hotfix commit:

```bash
touch fix-1.txt
git add fix-1.txt
git commit -m "hotfix work 1"

gitversion /showvariable MajorMinorPatch
gitversion /showvariable FullSemVer
gitversion /showvariable CommitsSinceVersionSource
```

Expected:

```text
0.1.0
0.1.0-hotfix-urgent.1
1
```

Create a second hotfix commit:

```bash
touch fix-2.txt
git add fix-2.txt
git commit -m "hotfix work 2"

gitversion /showvariable FullSemVer
gitversion /showvariable CommitsSinceVersionSource
```

Expected:

```text
0.1.0-hotfix-urgent.2
2
```

The hotfix pipeline should use `FullSemVer` for the protected hotfix tag:

```bash
git tag "$(gitversion /showvariable FullSemVer)"
```

### Case 3: Hotfix Backmerge Produces Next Stable Main Version

```bash
git switch main
git merge --no-ff hotfix/urgent -m "merge hotfix urgent"

gitversion /showvariable MajorMinorPatch
gitversion /showvariable FullSemVer
gitversion /showvariable CommitsSinceVersionSource
```

Expected:

```text
0.1.1
0.1.1-3
3
```

For the protected main/master production tag, use `MajorMinorPatch`, not
`FullSemVer`:

```bash
git tag "$(gitversion /showvariable MajorMinorPatch)"
```

### Case 4: Feature Tags Do Not Take Over Main Versioning

```bash
git switch -c feature/free-tag-test

touch feature-1.txt
git add feature-1.txt
git commit -m "feature work +semver: minor"

git tag "whatever-devs-want"
git tag "9.9.9-random-feature-tag"

git switch main
git merge --no-ff feature/free-tag-test -m "merge feature free-tag-test"

gitversion /showvariable MajorMinorPatch
gitversion /showvariable FullSemVer
gitversion /showvariable CommitsSinceVersionSource
```

Expected: the result must not be `9.9.9`. The free feature tag must not become
the main/master version source. Because the feature commit contains
`+semver: minor`, `MajorMinorPatch` should move to the next minor version.

Example:

```text
0.2.0
0.2.0-3
3
```

Tag the new stable main/master version:

```bash
git tag "$(gitversion /showvariable MajorMinorPatch)"
```

### Case 5: Major Bump From Feature History

```bash
git switch -c feature/major-test

touch breaking.txt
git add breaking.txt
git commit -m "breaking feature +semver: major"

git switch main
git merge --no-ff feature/major-test -m "merge feature major-test"

gitversion /showvariable MajorMinorPatch
```

Expected:

```text
1.0.0
```

### Helpful Inspection Commands

```bash
git tag --list
git log --oneline --decorate --graph --all
gitversion /showConfig
```

If your real repository uses squash merges, make sure `+semver: patch`,
`+semver: minor`, or `+semver: major` survives in the squash commit message.
Otherwise GitVersion cannot see the requested bump in the main/master history.
