# Salto Deploy (reference, loaded by the `/salto` router)

This is reference content. It is not registered as a slash command. The `/salto` router reads it when intent is classified as DEPLOY, then follows the instructions below with the user's original `$ARGUMENTS`.

> [!NOTE]
>
> Invoked via: /salto "<deploy request>" [--workspace <path>] [--deployment-id <id> | --branch-name <name>] [--max-local-iterations <n>] [--max-saas-iterations <n>]

Orchestrate NACL changes from edit to SaaS-validated PR. Handles both new and existing Salto deployments.

## Two modes

**Existing deployment** — pass `--deployment-id` or `--branch-name`. The skill edits locally, validates against the target env's state (auto-fetched), then runs `deployment preview` against that existing deployment.

**New deployment** (default) — no deployment ID provided. The skill edits and validates locally first (state auto-fetched from the target env), pushes, creates a PR via `gh` (or prints a compare URL as a fallback), then creates a Salto deployment from the PR via `salto-cli deployment create from-pull-request`.

In both modes, state is downloaded directly from the target environment — no "seed deployment" is needed.

## Guardrails

- All edits happen inside a git worktree on a `claude/<task-slug>` branch. Never modify the user's working tree.
- Never push until the local plan is clean (zero `changeErrors`). If `validate-local` fails for any reason, stop — do not push.
- Never force-push to any branch outside `claude/*`.
- Stop immediately on auth or credential errors. Report clearly and do not attempt to debug credentials.
- Bounded loops: max 5 local iterations, max 3 SaaS iterations. If either limit is hit, stop and summarise what remains unresolved.

## Instructions

Follow these steps in order. Stop and report clearly if any step fails.

### Step 1: Resolve workspace

If `--workspace <path>` is in `$ARGUMENTS`, use that path.

Otherwise, check if the current working directory is a Salto workspace:
```bash
[ -f "$(pwd)/salto.config/workspace.nacl" ]
```
- If yes → use CWD silently as the workspace. Print: `Using workspace: <cwd>`
- If no → stop: "Current directory is not a Salto workspace. Re-run with `--workspace <path>`."

Store the resolved absolute path as `WORKSPACE`.

### Step 2: Parse remaining arguments

From `$ARGUMENTS`, extract:
- **description** (required, positional) — short description of the change, used in branch name, commit, and PR title.
- `--deployment-id <id>` — forces existing-deployment mode; also used to fetch state.
- `--branch-name <name>` — identify existing deployment by its linked branch (forces existing-deployment mode).
- `--max-local-iterations <n>` — default 5.
- `--max-saas-iterations <n>` — default 3.

Derive a `task-slug` from the description: lowercase, spaces → hyphens, max 40 chars.

**Mode**: If `--deployment-id` or `--branch-name` was provided → **existing-deployment mode**. Otherwise → **new-deployment mode**.

### Step 3: Pre-flight checks

Run all checks and collect every failure before reporting. Do not stop at the first one.

1. **SALTO_API_TOKEN set**: `[ -n "$SALTO_API_TOKEN" ]` — if missing, add to failures: "SALTO_API_TOKEN is not set."
2. **salto-cli available**: `which salto-cli` — if missing, add to failures: "salto-cli not found in PATH."
2b. **gh CLI availability** (informational, never a failure): probe with `which gh >/dev/null && gh auth status >/dev/null 2>&1`. Set `GH_AVAILABLE=true` if both succeed, else `GH_AVAILABLE=false`. Used in Step 9 to decide whether to create the PR automatically or fall back to printing the compare URL.
3. **Is a Salto workspace**:
   - `salto.config/workspace.nacl` exists and contains a `uid` field → store as `WORKSPACE_UID`
   - **Detect workspace format**:
     - If `salto.config/envsSaltoCloud.nacl` exists and contains an `envsCloud = [...]` block → **cloud-mounted workspace**. Set `WORKSPACE_FORMAT=cloud`. Parse each `{ uuid = "...", folderName = "..." }` entry; use the `folderName` values as env names and the `uuid` values as env IDs. Store the first (or only) folderName as `ENV_NAME` and the first uuid as `ENV_UUID`. If multiple envs exist and the description doesn't disambiguate, ask the user which env to target (offer both name and uuid).
     - Else if `salto.config/envs.nacl` exists and defines at least one environment (`envs { envs = ["<name>", ...] }`) → **legacy workspace**. Set `WORKSPACE_FORMAT=legacy`. Store the first (or only) env name as `ENV_NAME`. Leave `ENV_UUID` unset. If multiple envs exist and the description doesn't disambiguate, ask the user which env to target.
   - List all adapter names as `ADAPTER_LIST` from `salto.config/adapters/`.
   - `salto.config/adapters/` directory exists.

   Print: `Workspace: <uid> | Env: <env-name> | Format: <legacy|cloud> | Adapters: <adapter-list>`

   If any file is missing or malformed, add to failures: "Not a valid Salto workspace — missing `<file>`."

4. **Git repository**: `git -C "${WORKSPACE}" rev-parse --show-toplevel` → store as `GIT_ROOT`. If fails, add to failures: "Workspace is not inside a git repository."

5. **Git remote (GitHub)**:
   - Run `git -C "${WORKSPACE}" remote get-url origin`
   - If no `origin`, add to failures: "No git remote 'origin' — workspace must be connected to GitHub."
   - If URL contains `github.com`, parse `owner/repo` → store as `GITHUB_REPO`. Print: `GitHub repo: <owner/repo>`
   - If URL does not contain `github.com`, add warning (non-fatal): "Remote is not a GitHub URL. Push and PR creation may fail."

6. **Remote reachable**: `git -C "${WORKSPACE}" ls-remote --exit-code origin HEAD` — if fails, add warning: "Cannot reach remote origin. Check git credentials."

7. **SaaS auth** (only if `SALTO_API_TOKEN` is set): run `salto-cli deployment list` and check output:
   - If "Authentication Failed" → add to failures: "SaaS authentication failed. Your token may be expired — generate a new SALTO_API_TOKEN in the Salto UI. If targeting staging, also set GRAPHQL_URL and SALTO_URL."

If any hard failures were collected, print them all and stop. Print warnings but continue.

### Step 3b: Load adapter knowledge (conditional)

From the adapter list extracted in step 3, check whether a knowledge file exists for each adapter and read it if so:
```bash
[ -f "${CLAUDE_PLUGIN_ROOT}/adapters/<adapter>.md" ] && cat "${CLAUDE_PLUGIN_ROOT}/adapters/<adapter>.md"
```

Do this for every adapter found. Missing adapter files are silently skipped — they are enrichment, not a requirement. When an adapter file is present, reading it before any NACL edits ensures Claude uses the correct element types, ID patterns, and avoids known pitfalls for that adapter.

### Step 4: Create git worktree

Capture the original branch **before** creating the worktree so the eventual PR can target it. This must be deterministic: read it from git, do not infer later from the worktree (the worktree is on the new branch by the time we'd look).

```bash
ORIGINAL_BRANCH=$(git -C "${GIT_ROOT}" symbolic-ref --short HEAD)
echo "Original branch: ${ORIGINAL_BRANCH}"

TIMESTAMP=$(date +%s)
BRANCH="claude/${task-slug}-${TIMESTAMP}"

git -C "${GIT_ROOT}" worktree add -b "${BRANCH}" "${GIT_ROOT}/../$(basename ${GIT_ROOT})-${BRANCH//\//-}"
```

If `git symbolic-ref` fails (detached HEAD), abort the run — we can't safely pick a PR base. Fall back to asking the user only as a last resort.

Capture the actual worktree path from git (do not compute it manually):
```bash
WORKTREE_PATH=$(git -C "${GIT_ROOT}" worktree list --porcelain \
  | grep -B1 "branch refs/heads/${BRANCH}" \
  | grep "^worktree " \
  | awk '{print $2}')
echo "Worktree: ${WORKTREE_PATH}"
```

All subsequent NACL edits happen inside `WORKTREE_PATH`. `ORIGINAL_BRANCH` is used in Step 9 as `--base` when creating the PR.

### Step 5: Prepare state temp dir

Create a temp directory for state files that will persist for the duration of this skill run:

```bash
STATE_TMP=$(mktemp -d -t salto-state-XXXXXX)
echo "State dir: ${STATE_TMP}"
```

This directory is:
- Outside any git tree (mktemp always uses `/tmp` or equivalent)
- Passed as `--state-dir` to every `validate-local` call
- Deleted at the end of the skill run

On the first `validate-local` call, if state files are absent from `STATE_TMP`, the CLI auto-fetches them directly from the target environment (via `--target-env`). On subsequent calls the files are already present and no fetch happens.

### Step 6: Local edit and validate loop (max: --max-local-iterations, default 5)

Repeat until the plan is clean or the limit is reached:

**6a. Make NACL edits**
- First iteration: apply the user's requested change inside `WORKTREE_PATH`.
- Subsequent iterations: fix the errors from the previous validate run.
- Keep edits small and scoped. Summarise in one line what changed.

**6b. Run validate-local**

On the **first** iteration of this loop, pass `--refresh-state` so the CLI wipes `STATE_TMP` and re-fetches the latest state from the target env. This guarantees a deploy starts against the freshest state — even if `STATE_TMP` somehow has files from a prior run.

For env targeting: use `--target-env-id "${ENV_UUID}"` when `WORKSPACE_FORMAT=cloud` (cloud orgs can have multiple envs with the same display name, which makes `--target-env` ambiguous). Use `--target-env "${ENV_NAME}"` when `WORKSPACE_FORMAT=legacy`.

```bash
# Cloud workspace
salto-cli deployment validate-local \
  --workspace "${WORKTREE_PATH}" \
  --target-env-id "${ENV_UUID}" \
  --state-dir "${STATE_TMP}" \
  --refresh-state \
  --output json \
  --allow-warnings

# Legacy workspace
salto-cli deployment validate-local \
  --workspace "${WORKTREE_PATH}" \
  --target-env "${ENV_NAME}" \
  --state-dir "${STATE_TMP}" \
  --refresh-state \
  --output json \
  --allow-warnings
```

On **subsequent** iterations (after a failed validate that you're now fixing), **drop `--refresh-state`**. State doesn't change while you edit NACL locally; re-downloading every iteration wastes time. Keep the same `--target-env-id` / `--target-env` flag you chose above.

State is fetched from the environment directly — no deployment seed is required. Works the same way in both new-deployment and existing-deployment mode.

Parse the JSON output:
- Collect `myElemIDs` = the set of `elemID` values from the plan's `planItems` (i.e. elements this run is adding/modifying/removing).
- Collect `relevantErrors` = `changeErrors` whose `elemID` is in `myElemIDs`.
- Collect `baselineErrors` = `changeErrors` whose `elemID` is NOT in `myElemIDs`.

Then decide:
- `relevantErrors` is empty → **plan is clean for your change.** Break the loop and proceed to push, even if `baselineErrors` is non-empty. The skill is responsible only for the change it's making, not for fixing pre-existing workspace drift.
  - Log: `Plan clean: 0 errors on my elements (${myElemIDs.length} planned). Ignoring ${baselineErrors.length} pre-existing baseline errors.`
- `relevantErrors` is non-empty → note each error's `elemID`, `severity`, `message`; grep `WORKTREE_PATH` for the elemID; plan a targeted fix on the next iteration.

**6c. If validate-local fails to run at all** (stale state, missing files, env resolution failure, CLI exits non-zero with no parseable JSON):
- **Do not push. Do not commit.**
- Print the exact error and stop.
- Exit code 3 with valid JSON output is *not* a hard failure — it means the plan was produced but contains changeErrors. Apply the `relevantErrors` filter above to decide whether to continue.

**6d. Max iterations without clean plan**: Stop. Summarise remaining errors and what was tried. Ask the user how to proceed. Do not push.

**6e. Security issues** (`securityIssues` field in the JSON output): a list of security rule violations detected on the workspace elements (e.g. weak password policy, missing MFA, broad permissions). Each entry has `accountName`, `key`, `severity` (`CRITICAL`/`HIGH`/`MEDIUM`/`LOW`), `title`, and `occurrences[]` listing the offending elements.

- Filter to issues whose any `occurrences[].elemId` is in `myElemIDs` → `relevantSecurityIssues`. These are issues *introduced or aggravated by this change*.
- Filter to issues whose all `occurrences[].elemId` are outside `myElemIDs` → `baselineSecurityIssues`. Pre-existing.
- Treatment:
  - `CRITICAL` or `HIGH` severity in `relevantSecurityIssues` → **block the push**, surface the issue list, ask the user how to proceed. Don't auto-fix.
  - `MEDIUM`/`LOW` in `relevantSecurityIssues` → print a warning and continue (still push).
  - `baselineSecurityIssues` (any severity) → log a one-line summary count (`Ignoring N pre-existing security issues unrelated to this change`) and continue. Never block on baseline.

### Step 7: Commit (no push yet in new-deployment mode)

Stage and commit only the user-facing NACL edits. The skill no longer touches `salto.config/envs.nacl` for cloud workspaces — the CLI's `validate-local` synthesises the legacy-format envs.nacl into its shadow workspace and reads the authoritative `accountToServiceName` mapping from the env-info sidecar that `fetch-state` writes to the state dir. So there's nothing to restore before commit.

```bash
git -C "${WORKTREE_PATH}" add -- '*.nacl'
git -C "${WORKTREE_PATH}" commit -m "${description}"
```

**Existing-deployment mode**: continue to Step 8 (push).
**New-deployment mode**: print: "Local plan is clean. Branch committed but not yet pushed."

### Step 8: Push branch

```bash
git -C "${WORKTREE_PATH}" push -u origin "${BRANCH}"
```

### Step 9: Open the PR

Pick a path based on the pre-flight detection:

**Path A — `gh` available and the remote is GitHub** (`GH_AVAILABLE=true` AND `GITHUB_REPO` is set): create the PR programmatically. Do not open a browser. Do not ask the user to do anything in the UI.

```bash
PR_URL=$(gh pr create \
  --repo "${GITHUB_REPO}" \
  --head "${BRANCH}" \
  --base "${ORIGINAL_BRANCH}" \
  --title "${description}" \
  --body "Created by /salto-deploy.

Local validate-local plan is clean (zero changeErrors).

Salto deployment will be auto-created from this PR by the GitHub webhook." 2>&1)
```

If `gh pr create` exits non-zero:
- If the output contains "already exists for" → a PR is already open for this branch. Recover it:
  ```bash
  PR_URL=$(gh pr view "${BRANCH}" --repo "${GITHUB_REPO}" --json url -q .url)
  ```
- Otherwise stop and print the `gh` error verbatim. Do not retry blindly.

Print: `PR created: ${PR_URL}`

**Path B — `gh` not available but the remote is GitHub** (`GH_AVAILABLE=false` AND `GITHUB_REPO` is set): fall back to printing the compare URL for manual creation.

```bash
COMPARE_URL="https://github.com/${GITHUB_REPO}/compare/${ORIGINAL_BRANCH}...${BRANCH}?expand=1"
```

Print:
> "Branch pushed. `gh` is not installed or not authenticated, so I cannot create the PR for you.
> Open this URL to create the PR:
> **`${COMPARE_URL}`**
>
> Once you've opened the PR, paste the PR URL here."

Wait for the user to paste the PR URL → store as `PR_URL`.

**Path C — remote is not GitHub** (`GITHUB_REPO` is unset): no webhook-based deployment creation is possible. Tell the user:
> "Branch pushed to a non-GitHub remote. Open a PR in your hosting service, then either:
> 1. Create a deployment manually in the Salto UI and re-run with `--deployment-id <id>`, or
> 2. Re-run with `--branch-name ${BRANCH}` if your stack auto-creates deployments via some other mechanism."

Then stop the skill — Step 10 onwards requires a Salto deployment that won't exist.

### Step 10: Create the Salto deployment from the PR

**Existing-deployment mode**: deployment ID is already known from `--deployment-id` / `--branch-name`. Skip this step.

**New-deployment mode (Path A or B from Step 9 — we have a `PR_URL`)**: create the deployment directly via the CLI. This is synchronous and does not depend on the GitHub webhook being wired.

Use `--target-env-id "${ENV_UUID}"` when `WORKSPACE_FORMAT=cloud` and `--target-env "${ENV_NAME}"` when `WORKSPACE_FORMAT=legacy` — same selection rule as Step 6b. Cloud orgs can have multiple envs sharing a display name across orgs the user belongs to, so the name lookup fails with "Found multiple environments with name …" even when the worktree only points at one. The UUID is unambiguous.

```bash
# Cloud workspace
DEPLOYMENT_JSON=$(salto-cli deployment create from-pull-request \
  --pr-url "${PR_URL}" \
  --target-env-id "${ENV_UUID}" 2>&1)

# Legacy workspace
DEPLOYMENT_JSON=$(salto-cli deployment create from-pull-request \
  --pr-url "${PR_URL}" \
  --target-env "${ENV_NAME}" 2>&1)

DEPLOYMENT_ID=$(echo "$DEPLOYMENT_JSON" | python3 -c \
  "import sys, json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
```

`from-pull-request` outputs JSON by default — it does not accept `--output`. Don't add that flag.

If `DEPLOYMENT_ID` is set: print `Deployment ${DEPLOYMENT_ID} created from PR.` and continue.

If `from-pull-request` fails (non-zero exit, no JSON, or empty `id`), fall back to polling for a webhook-created deployment (Salto's GitHub webhook may create it independently):

```bash
for i in $(seq 1 18); do
  RESULT=$(salto-cli deployment list --branch-name "${BRANCH}" 2>/dev/null)
  DEPLOYMENT_ID=$(echo "$RESULT" | python3 -c \
    "import sys, json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null)
  [ -n "$DEPLOYMENT_ID" ] && break
  sleep 5
done
```

If still empty after polling, stop:
> "Could not create or find a deployment for branch `${BRANCH}`. Last error from `from-pull-request`:
> ```
> ${DEPLOYMENT_JSON}
> ```
> Options:
> 1. Verify the target env has `deploymentBranchingType=ENV_BASE_BRANCH`, is connected to a git repo, and `pushSettings=AUTOMATIC` — these are the preconditions for `createDeploymentFromPR`.
> 2. Open the Salto UI → create a deployment manually → re-run with `--deployment-id <id>`.
> 3. Re-run with `--branch-name ${BRANCH}` after waiting for the webhook to fire."

### Step 11: SaaS preview loop (max: --max-saas-iterations, default 3)

Repeat until preview is clean or limit reached:

**11a. Run preview**
```bash
salto-cli deployment preview \
  --deployment-id "${DEPLOYMENT_ID}" \
  --output json \
  --allow-warnings
```

**11b. Clean** → proceed to Step 12.

**11c. Errors found** → fix NACLs, commit, push:
```bash
git -C "${WORKTREE_PATH}" add -- '*.nacl'
git -C "${WORKTREE_PATH}" commit -m "fix: <error summary>"
git -C "${WORKTREE_PATH}" push origin "${BRANCH}"
```

**11d. Max iterations reached**: Stop. Summarise remaining errors. Leave PR open for manual inspection.

### Step 12: Finish

Print:
> "SaaS preview is clean. PR is ready for review:
> **`${PR_URL}`**"

Print summary: PR URL, deployment ID, branch, local iterations, SaaS iterations, changes made.

Cleanup:
```bash
rm -rf "${STATE_TMP}"
```

Remind the user: worktree at `WORKTREE_PATH` is left for inspection. To remove: `git worktree remove "${WORKTREE_PATH}"`.

## Usage examples

```
# From the workspace directory — no --workspace needed:
cd ~/path/to/your/salto-workspace
/salto-deploy "add Zendesk trigger ai_review_test that tags new tickets"

# Explicit workspace path:
/salto-deploy "rename Okta group admins to platform-admins" --workspace ~/salto-workspaces/prod

# Existing deployment (state fetched from it; preview runs against it):
/salto-deploy "fix salesforce field label" --deployment-id abc123
```

## Notes

- `validate-local` runs without adapter credentials. When state is missing, it auto-fetches from the provided `--deployment-id`.
- SaaS preview and state fetching both require `SALTO_API_TOKEN`.
- For staging environments, also export `GRAPHQL_URL` and `SALTO_URL` before running.
- New-deployment mode relies on Salto's GitHub webhook. If the workspace isn't connected to GitHub, create the deployment manually in the UI and re-run with `--deployment-id`.
- On auth errors (403, "Authentication Failed"), stop immediately — do not attempt to debug credentials.
