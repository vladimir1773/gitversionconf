# Manual tests for the Helm GitVersion configuration

Run these commands from this repository. They create a disposable Git
repository and do not modify the current repository.

## Setup

```bash
cd "/Users/vladimir/Documents/New project 2/gitversionconf"

HELM_TEST_DIR="$(mktemp -d /tmp/gitversion-helm-manual.XXXXXX)"
cp GitVersion.helm.yml "$HELM_TEST_DIR/GitVersion.yml"
cd "$HELM_TEST_DIR"

git init -b main
git config user.name "Manual Helm Test"
git config user.email "manual-helm-test@example.local"

touch Chart.yaml
git add Chart.yaml GitVersion.yml
git commit -m "initial chart"
```

The first chart version is `0.0.1`:

```bash
gitversion /showvariable MajorMinorPatch
```

Expected:

```text
0.0.1
```

Create a protected baseline tag as the pipeline would:

```bash
git tag 0.1.0
```

## Feature tags and minor bump

Create a feature branch with arbitrary preview tags. These tags deliberately do
not match the protected stable tag pattern `^v?\d+\.\d+\.\d+$`.

```bash
git switch -c feature/chart-change

touch values.yaml
git add values.yaml
git commit -m "feat: add chart values"

git tag preview-chart-change
git tag 9.9.9-feature-preview.7

gitversion /showvariable FullSemVer
git tag --list
```

Merge the complete feature history and calculate the stable chart version:

```bash
git switch main
git merge --no-ff feature/chart-change -m "merge feature/chart-change"

gitversion /showvariable MajorMinorPatch
gitversion /showvariable FullSemVer
```

`MajorMinorPatch` must be `0.2.0`. Neither feature tag may turn it into `9.9.9`.
The release pipeline would now create the authoritative tag like this:

```bash
git tag "$(gitversion /showvariable MajorMinorPatch)"
```

## Patch bump

```bash
git switch -c feature/chart-fix

touch template-fix.yaml
git add template-fix.yaml
git commit -m "fix: correct chart template"

git switch main
git merge --no-ff feature/chart-fix -m "merge feature/chart-fix"
gitversion /showvariable MajorMinorPatch
```

Expected: `0.2.1`. Then emulate the pipeline tag:

```bash
git tag "$(gitversion /showvariable MajorMinorPatch)"
```

## Explicit major bump

```bash
git switch -c feature/breaking-chart-change

touch breaking.yaml
git add breaking.yaml
git commit -m "feat!: change chart contract"

git switch main
git merge --no-ff feature/breaking-chart-change \
  -m "merge feature/breaking-chart-change"
gitversion /showvariable MajorMinorPatch
```

Expected: `1.0.0`.

The equivalent non-Conventional-Commit marker is `+semver: major`. The supported
explicit markers are:

```text
+semver: patch
+semver: minor
+semver: major
+semver: none
```

## Test master instead of main

The configuration key is named `main`, but its regex supports both real branch
names. Test that in a second disposable repository:

```bash
cd "/Users/vladimir/Documents/New project 2/gitversionconf"

HELM_MASTER_DIR="$(mktemp -d /tmp/gitversion-helm-master.XXXXXX)"
cp GitVersion.helm.yml "$HELM_MASTER_DIR/GitVersion.yml"
cd "$HELM_MASTER_DIR"

git init -b master
git config user.name "Manual Helm Test"
git config user.email "manual-helm-test@example.local"
touch Chart.yaml
git add Chart.yaml GitVersion.yml
git commit -m "initial chart"
git tag 0.1.0

git switch -c feature/master-fix
touch fix.yaml
git add fix.yaml
git commit -m "fix: patch chart on master"
git switch master
git merge --no-ff feature/master-fix -m "merge feature/master-fix"

gitversion /showvariable MajorMinorPatch
```

Expected: `0.1.1`.

## Automated equivalent

The repository also contains the repeatable version of these checks:

```bash
cd "/Users/vladimir/Documents/New project 2/gitversionconf"
./scripts/run-helm-tests.sh
```

Useful diagnostic commands:

```bash
gitversion /showConfig
gitversion
git log --oneline --decorate --graph --all
git tag --list
```

For squash merges, preserve `fix:`, `feat:`, `feat!:`, `BREAKING CHANGE:`, or
the relevant `+semver:` marker in the final squash commit message. GitVersion
can only evaluate bump instructions that are present in the history of
`main` / `master`.
