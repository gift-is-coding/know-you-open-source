# Public repository synchronization

This is the maintainer workflow for publishing KnowYou source without exposing private fundraising material. The private repository is the canonical product-code source. The public repository receives reviewed snapshots and external public contributions flow back into the private repository before the next snapshot.

## Security invariants

- Never run history rewriting in the private repository.
- Never push directly from `scripts/create-public-history.sh` or `scripts/export-public-repo.sh`; both tools intentionally stop before network mutation.
- The public tree is fail-closed: only paths in `config/public-files.txt` are exported.
- Every prefix in `config/public-deny-paths.txt` is rejected even if somebody also adds it to the allowlist.
- `docs/investor-pitch/` and `docs/fundraising/` must be absent from every reachable public commit.
- A destination checkout must be clean before synchronization. The exporter refuses to overwrite local or untracked work.
- Gitleaks is mandatory unless a maintainer deliberately passes `--skip-gitleaks`. Skipping it is never acceptable for a real publication.
- Gitleaks exceptions in `.gitleaks.toml` must constrain both the exact value and exact path. Do not ignore an entire rule, directory, or file merely to make CI green.

## Prerequisites

- Commit the private source state that should be published.
- Install Gitleaks 8.30.1 or provide an executable through `GITLEAKS_BIN`.
- Keep the private and public repositories in separate directories.
- Create an empty GitHub repository for the public destination, but do not add it as a private-repository push remote.

The scripts accept `--gitleaks-bin /absolute/path/to/gitleaks` when Gitleaks is not on `PATH`.

## One-time public history creation

Run this from the reviewed private checkout after the open-source changes have reached the branch being published:

```bash
./scripts/create-public-history.sh \
  --source-repo . \
  --source-branch main \
  --destination ../know-you-public
```

The command:

1. requires a destination path that does not exist
2. clones only the selected private branch without tags
3. removes the private remote before rewriting anything
4. applies the current public allowlist to every reachable commit and removes every denied or unlisted path
5. deletes rewrite backup refs, expires reflogs, and prunes unreachable objects
6. replaces the current tree with the public allowlisted snapshot
7. records the private source SHA in `.public-sync/source.json` and the sync commit trailer
8. verifies the current tree and scans the sanitized history with Gitleaks
9. leaves a clean local repository with no remote and performs no push

Before the first push, inspect the result:

```bash
git -C ../know-you-public status --short --branch
git -C ../know-you-public log --all -- docs/investor-pitch docs/fundraising
git -C ../know-you-public remote -v
GITLEAKS_BIN="$(command -v gitleaks)" \
  ../know-you-public/scripts/verify-public-repo.sh --root ../know-you-public
gitleaks git ../know-you-public \
  --config ../know-you-public/.gitleaks.toml \
  --gitleaks-ignore-path ../know-you-public/.gitleaksignore \
  --redact --no-banner
```

The denied-path log and remote list must both be empty. Review the complete tracked-file list before adding the new public remote. Do not push historical private tags during initial publication.

After review, add the empty public repository and push only the sanitized branch:

```bash
git -C ../know-you-public remote add origin <PUBLIC_REPOSITORY_URL>
git -C ../know-you-public push --set-upstream origin main
```

Pushing remains a deliberate maintainer action and requires the repository's normal approval policy.

## Routine private-to-public synchronization

Use a dedicated clean checkout of the public repository:

```bash
private_sha="$(git rev-parse main)"
sync_branch="sync/private-${private_sha:0:12}"

./scripts/export-public-repo.sh \
  --source-repo . \
  --source-ref main \
  --destination ../know-you-public \
  --branch "$sync_branch" \
  --commit
```

The exporter checks out the committed private ref through an isolated Git index, not the working tree. This preserves every allowlisted path even when release-oriented `.gitattributes` rules mark it `export-ignore`. It verifies the staged snapshot before changing the public checkout, replaces the public checkout only when it is clean, and creates a commit with:

```text
sync: private <12-character-source-SHA>

Public-Source-Commit: <full-private-SHA>
```

`.public-sync/source.json` contains the same full private SHA. The public commit containing that file is the corresponding public SHA, so the mapping remains available through normal Git history.

Review and publish the prepared branch manually:

```bash
git -C ../know-you-public status --short --branch
git -C ../know-you-public show --stat --oneline HEAD
git -C ../know-you-public push --set-upstream origin "$sync_branch"
gh -R <OWNER/PUBLIC_REPOSITORY> pr create \
  --base main \
  --head "$sync_branch" \
  --title "sync: private ${private_sha:0:12}" \
  --body "Allowlisted source sync from private commit $private_sha."
```

Do not merge until the public repository gate passes.

## Public contribution backflow

The public repository may accept normal pull requests. Before the next private-to-public export:

1. merge the public pull request
2. fetch the merged public commit into the private repository using a read-only public remote
3. cherry-pick or reimplement that commit on a private feature branch
4. run the private repository verification suite and merge it into private `main`
5. perform the next allowlisted export from private `main`

Do not leave a public-only product change outside the private canonical branch; the next snapshot intentionally replaces the public tree and would remove it.

Prefer commits that contain either public product changes or private material changes, not both. A mixed commit can still be exported as a snapshot, but it is harder to review, backport, and attribute.

## CI gate

`.github/workflows/public-repository-gate.yml` runs on every public pull request and push to `main`. It checks:

- synchronization-script behavior and failure cases
- denied paths, sensitive filenames, required legal files, and GPL-3.0
- current-tree and complete-history Gitleaks scans
- macOS app test, build, and analysis
- Networking Web audit, typecheck, lint, test, and build
- My Wiki audit, typecheck, build, mock tests, Rust check, and Rust tests
- My Wiki MCP audit and tests

Required branch protection should require all workflow jobs before merging into public `main`.

## Troubleshooting

- `destination Git checkout must be clean`: commit, stash, or remove local public-checkout changes before retrying. Do not bypass this guard.
- `allowlist overlaps denied path`: narrow the allowlist. Never weaken the deny list to export a parent directory.
- `allowlist path does not exist`: the allowlist and selected source ref disagree; update them together in a committed private change.
- Gitleaks finding: inspect the exact value, file, and history. Rotate a real credential before proceeding. Only add a narrowly constrained exception for a value proven public or synthetic.
- no-op synchronization: the selected private source SHA already produces the same public snapshot, so no commit is created.
