# GitVersion configuration

This repository uses GitVersion to calculate versions for a CD deploy-repo
branching model with three relevant branch families:

- `main`
- `hotfix/*`
- `feature/*`

`release/*` and `develop` are intentionally out of scope for this repository.

## What GitVersion does here

GitVersion calculates the semantic version and branch-specific pre-release
label. It does not enforce deployment approvals, protected tags, production
usage, or environment promotion order. Those rules must be implemented in the
Git host and CI/CD pipeline.

The expected protected production tag format is:

```text
<MajorMinorPatch>-<PreReleaseLabel>
```

Examples:

```text
0.0.1-release
0.0.1-hotfix
```

Do not use `FullSemVer` for protected production tags, because untagged
pre-release builds include an additional counter, for example:

```text
0.0.1-release.1
0.0.1-hotfix.1
```

## Top-level settings

### `workflow: GitHubFlow/v1`

GitHubFlow is used because this deploy repo has a simple mainline model:
changes flow through `main`, with temporary `feature/*` and `hotfix/*`
branches. Long-lived `develop` and `release/*` branches are not part of the
model.

### `mode: ContinuousDelivery`

Continuous Delivery mode keeps producing stable, predictable pre-release
versions from each branch until an explicit tag exists.

For example, on `main` GitVersion can produce:

```text
0.0.1-release.1
```

The pipeline can then create the protected tag:

```text
0.0.1-release
```

### `tag-prefix: '[vV]?'`

This allows GitVersion to understand both tag styles:

```text
0.0.1-release
v0.0.1-release
```

The `v` prefix is optional.

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

Patch is the default branch increment, but these messages allow intentional
minor and major releases without changing the GitVersion config.

## Branches

### `main`

```yaml
main:
  regex: ^main$
  label: release
  mode: ContinuousDelivery
  increment: Patch
```

`main` represents the blue main pipeline in the diagram.

The chosen label is:

```text
release
```

That means the calculated pre-release version on `main` looks like:

```text
0.0.1-release.1
```

The pipeline should use `MajorMinorPatch` and `PreReleaseLabel` to create the
protected release tag:

```text
0.0.1-release
```

`increment: Patch` is the default increment for normal mainline movement.
The larger jumps shown in the diagram are handled explicitly through
commit-message incrementing:

```text
0.0.1 -> 0.1.0 -> 1.0.0 -> 1.1.0 -> 2.0.0
```

Patch is the safe default. Minor and major jumps should be requested explicitly
through commit messages such as `+semver: minor` or `+semver: major`.

### `prevent-increment`

```yaml
prevent-increment:
  of-merged-branch: true
  when-current-commit-tagged: true
```

This avoids accidental extra bumps when a branch has already contributed its
version or when the current commit is already tagged.

### `source-branches`

```yaml
source-branches:
  - feature
  - hotfix
```

This does not mean GitVersion checks out or uses those branches as a fixed
base. It means GitVersion may interpret `feature/*` and `hotfix/*` branches as
valid sources that can be merged into `main`.

### `hotfix/*`

```yaml
hotfix:
  regex: ^hotfix(es)?[/-](?<BranchName>.+)
  label: hotfix
  mode: ContinuousDelivery
  increment: Patch
```

`hotfix/*` represents the green hotfix pipeline in the diagram.

The chosen label is:

```text
hotfix
```

That means GitVersion can calculate:

```text
0.0.1-hotfix.1
```

The pipeline should create the protected hotfix tag from
`MajorMinorPatch` and `PreReleaseLabel`:

```text
0.0.1-hotfix
```

`source-branches` is restricted to `main`:

```yaml
source-branches:
  - main
```

This documents the intended flow: hotfix branches are created from `main`.

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

`increment: Inherit` lets the feature branch inherit the increment strategy
from its source branch instead of defining a separate release policy.

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

That keeps unexpected branches from looking like protected `release` or
`hotfix` builds.

## What must be enforced outside GitVersion

The following rules are part of the concept, but not enforceable by
GitVersion.yml:

- protected tag creation
- tag naming restrictions
- production deployment approval
- hotfix additional approval
- environment order such as `d0/1 -> u0/u1 -> t0/t1 -> p0`
- feature-only x0 deployment
- blocking `release/*` and `develop` in CI

Recommended protected tag patterns:

```text
^v?\d+\.\d+\.\d+-release$
^v?\d+\.\d+\.\d+-hotfix$
```

These should be implemented in the Git host and CI/CD pipeline.
