# Salto Deploy (reference, loaded by the `/salto` router)

This is reference content. It is not registered as a slash command. The `/salto` router reads it when intent is classified as DEPLOY, then follows the instructions below with the user's original `$ARGUMENTS`.

> [!NOTE]
>
> Invoked via: /salto "<deploy request>" [--workspace <path>] [--deployment-id <id> | --branch-name <name>] [--max-local-iterations <n>] [--max-saas-iterations <n>] [--ticket <id-or-url>]

Orchestrate NACL changes from edit to SaaS-validated PR. Handles both new and existing Salto deployments.

All deterministic orchestration (pre-flight checks, env resolution, worktree/state-dir setup, plan classification) lives in `salto-cli` — invoke the commands and read their JSON. Do not re-implement any of it in shell; the remaining shell in this workflow is limited to `git`/`gh`/`az` one-liners that work identically on macOS, Linux and Windows.

## Two modes

**Existing deployment** — pass `--deployment-id` or `--branch-name`. The skill edits locally, validates against the target env's state (auto-fetched), then runs `deployment preview` against that existing deployment.

**New deployment** (default) — no deployment ID provided. The skill edits and validates locally first (state auto-fetched from the target env), pushes, creates a PR via the git host's CLI (`gh` for GitHub, `az repos` for Azure DevOps — or prints a create URL as a fallback), then creates a Salto deployment from the PR via `salto-cli deployment create from-pull-request`.

In both modes, state is downloaded directly from the target environment — no "seed deployment" is needed.

## Guardrails

- All edits happen inside a git worktree on a `salto/<task-slug>` branch (created by `salto-cli deployment prepare-worktree`). Never modify the user's working tree.
- Never push until the local plan is clean (zero relevant `changeErrors`). If `validate-local` fails for any reason, stop — do not push.
- Never force-push to any branch outside `salto/*`.
- Stop immediately on auth or credential errors. Report clearly and do not attempt to debug credentials.
- Bounded loops: max 5 local iterations, max 3 SaaS iterations. If either limit is hit, stop and summarise what remains unresolved.

## Supported scenario: PR base = env's tracked branch (Path A only)

This skill **only** supports the case where the PR it opens targets the same branch the target env is tracking ("Path A" in Salto's `createDeploymentFromPR` resolver — works for every adapter). When the PR's base differs from the env's tracked branch (Path B), the Salto backend only supports Salesforce and NetSuite; any other adapter fails with "Environment does not have a supported application connection".

`salto-cli deployment preflight` enforces this: it fails (with remediation options) when the current branch doesn't match the env's tracked branch. If the user actually wants to deploy to `main` while sitting on another branch, they should `git checkout main` first; if they want the env to track their branch, they should reconfigure the env in the Salto UI (Env settings → Git), then re-run `/salto`.

## CLI JSON contracts used by this workflow

`salto-cli deployment preflight --workspace <path> [-e <env-name> | -E <env-id>]` — every pre-deploy check in one call. Exit 0 when `ok: true`; non-zero otherwise (JSON is still printed).

```json
{
  "ok": true,
  "failures": [], "warnings": [],
  "workspace": { "path": "...", "uid": "...", "format": "cloud|legacy", "adapters": ["netsuite"], "envs": [{ "name": "ns1", "id": "<uuid>" }] },
  "git": { "root": "...", "currentBranch": "main", "dirty": false, "remoteUrl": "...", "remote": { "provider": "github", "repo": "owner/repo" }, "remoteReachable": true },
  "auth": { "tokenPresent": true, "ok": true },
  "env": { "envId": "<uuid>", "envName": "ns1", "orgId": "<uuid>", "gitDetails": { "provider": "GITHUB", "repoName": "owner/repo", "remoteBranchName": "main" } },
  "branchMatch": { "currentBranch": "main", "envTrackedBranch": "main", "match": true }
}
```

For Azure DevOps remotes, `git.remote` is `{ "provider": "azure", "organization": "...", "project": "...", "repo": "..." }`.

`salto-cli deployment prepare-worktree --workspace <path> --slug <task-slug> --pull` — dirty-tree check, ff-only pull, `salto/<slug>-<timestamp>` branch + worktree, temp state dir:

```json
{ "branch": "salto/<slug>-<ts>", "worktreePath": "...", "stateDir": "...", "gitRoot": "...", "baseBranch": "main", "baseCommit": "<sha>" }
```

`salto-cli deployment ship --workspace <worktree> --target-env-id <id> --title <t> --body-file <f> --base <branch> --allow-warnings` — the whole post-edit tail in one call: commit NACL changes, push, open (or reuse) the GitHub PR, create the Salto deployment from it, wait for the SaaS preview, print the plan summary. With `--allow-warnings` (always pass it — warnings are surfaced in `changeErrors.relevant` for you to report): exit 0 = preview clean or warnings only; exit 3 = Error-severity changeErrors remain (the PR and deployment still exist — continue with the fix loop). GitHub remotes only; on other hosts use the granular fallback.

```json
{
  "branch": "salto/<slug>-<ts>",
  "prUrl": "https://github.com/owner/repo/pull/7",
  "deployment": { "id": "<uuid>", "name": "...", "status": "PREVIEW", "url": "https://app.salto.io/..." },
  "summary": { "adds": 1, "modifies": 0, "removes": 0 },
  "planElemIds": ["..."],
  "changeErrors": { "relevant": [], "baseline": [] },
  "planUrl": "https://app.salto.io/..."
}
```

`salto-cli deployment validate-local ... -o summary` and `salto-cli deployment preview ... -o summary` — compact plan with relevance classification already done:

```json
{
  "summary": { "adds": 1, "modifies": 0, "removes": 0 },
  "planElemIds": ["netsuite.location.instance.SF_HQ@s"],
  "changeErrors": { "relevant": [ { "elemID": "...", "severity": "Error|Warning|Info", "message": "..." } ], "baseline": [] },
  "securityIssues": { "relevant": [ { "key": "...", "severity": "CRITICAL|HIGH|MEDIUM|LOW", "title": "...", "occurrenceElemIds": [] } ], "baseline": [] }
}
```

`relevant` = on elements this plan touches; `baseline` = pre-existing workspace drift. `preview -o summary` additionally includes `planUrl` and has no `securityIssues`. Both commands accept `--plan-file <path>` to also write the full plan JSON (the `-o json` shape) to a file — use `<STATE_DIR>/plan.json`; the CLI guarantees it survives `--refresh-state`.

## Instructions

Follow these steps in order. Stop and report clearly if any step fails.

### Step 1: Resolve workspace

If `--workspace <path>` is in `$ARGUMENTS`, use that path. Otherwise check if the current working directory contains `salto.config/workspace.nacl`:

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
- `--ticket <id-or-url>` — the work item / ticket this change belongs to, in **any** ticketing system (Jira issue key, Azure DevOps work-item id or URL, etc.). Used in Step 10b to comment back on the ticket. (`--jira <issue-key>` is accepted as an alias.)

**Detect an involved ticket.** If `--ticket`/`--jira` was not passed, scan the description for a recognizable ticket reference — for example:
- a Jira-style key: `[A-Z][A-Z0-9]+-[0-9]+` (e.g. `SALTO-1234`);
- an Azure DevOps work item: `AB#<n>` or a `dev.azure.com/.../_workitems/edit/<n>` URL;
- any other ticket URL the user includes in the description.

Then: exactly one match → store it as `TICKET_REF` and print `Ticket: <ref>`; multiple distinct matches → ask the user which one is the ticket for this change; none → leave `TICKET_REF` empty (Step 10b is skipped).

**If the ticket *is* the task** (the request points at a ticket / work item instead of spelling out the change), fetch its content first — using the tool that matches where the ticket lives:
- **Azure DevOps** work item → `az boards work-item show --id <n> --organization https://dev.azure.com/<org> --output json` (needs the `azure-devops` extension; the `AZ_AVAILABLE` probe from Step 3). Use `az` whenever the workspace remote is Azure DevOps — the same way Step 9 uses `az repos` for the PR.
- **Otherwise** → a connected ticketing MCP (e.g. Jira).

Read the ticket's title/description to derive the actual change, then continue the workflow. Don't infer the change from the ticket id alone.

**Decisions log.** Initialize an empty `DECISIONS_LOG`. From here on, whenever the user makes a decision during this run — answers a clarifying question (target env, which ticket), approves pushing despite warnings, decides how to handle a security issue (Step 6e) or an iteration-limit stop (Steps 6d/11d), or changes scope — append a one-line `question → user's answer` entry. Step 10b posts these to the ticket.

Derive a `task-slug` from the description: a few lowercase words joined by hyphens (the CLI normalizes it further).

**Mode**: If `--deployment-id` or `--branch-name` was provided → **existing-deployment mode**. Otherwise → **new-deployment mode**.

### Step 3: Pre-flight — one CLI call

```
salto-cli deployment preflight --workspace "<WORKSPACE>"
```

If the workspace defines multiple environments, preflight fails asking for disambiguation — ask the user which env to target (offer the `workspace.envs` list from the output), then re-run with `-E <env-id>`.

Interpret the JSON:

- `ok: false` → print every entry in `failures` and stop. (The failure messages include remediation — e.g. the branch-mismatch failure explains the Path A options.)
- `warnings` non-empty → print them and continue.
- `ok: true` → store for later steps:
  - `ENV_UUID` = `env.envId`, `ENV_NAME` = `env.envName`, `ORG_ID` = `env.orgId`
  - `ADAPTER_LIST` = `workspace.adapters`
  - `ORIGINAL_BRANCH` = `git.currentBranch` (this is the PR's base branch)
  - `GIT_PROVIDER` = `git.remote.provider`; for github also `GITHUB_REPO` = `git.remote.repo`; for azure also `ADO_ORG`/`ADO_PROJECT`/`ADO_REPO` from `git.remote`.

  Print: `Workspace: <uid> | Env: <ENV_NAME> | UUID: <ENV_UUID> | Adapters: <ADAPTER_LIST> | Git: <provider> <repo> @ <ORIGINAL_BRANCH>`

From here on, **every CLI call that targets an env uses `--target-env-id "<ENV_UUID>"`** — never the env-name form (env names are not unique across orgs).

**PR-tool availability probe** (informational, never a failure):
- GitHub remote: `gh auth status` → `GH_AVAILABLE=true|false`.
- Azure DevOps remote: `az repos -h` → `AZ_AVAILABLE=true|false`.

### Step 3b: Load adapter knowledge (conditional)

For each adapter in `ADAPTER_LIST`, read its knowledge file if one is bundled with this skill: `{{SKILL_ROOT}}/adapters/<adapter>/<adapter>.md`. Missing adapter files are silently skipped — they are enrichment, not a requirement.

**Salesforce sub-adapters (CPQ / RLM-RCA):** for the `salesforce` adapter, also inspect the workspace data config (`fetch.data.includeObjects` in `salto.config/adapters/salesforce/salesforce.nacl`) and additionally read the matching sub-adapter file:

- `includeObjects` contains `SBQQ__` or `sbaa__` → `{{SKILL_ROOT}}/adapters/salesforce/cpq.md`.
- `includeObjects` contains RLM objects (`ProductClassification`, `AttributeDefinition`, `RateCard`, `ProductSellingModel`, …) → `{{SKILL_ROOT}}/adapters/salesforce/rlm.md`. (RLM is Salesforce's Revenue Cloud Advanced / **RCA** — same product, renamed; our code still calls it RLM.)

### Steps 4–5: Create the worktree and state dir — one CLI call

```
salto-cli deployment prepare-worktree --workspace "<WORKSPACE>" --slug "<task-slug>" --pull
```

`--pull` fast-forwards `ORIGINAL_BRANCH` from origin first, so the local plan runs against the freshest base (skipping it would surface other people's already-deployed changes as noise). The command fails with a clear message on a dirty working tree, detached HEAD, or a diverged branch — print the error and stop; those need the user's hands.

From the JSON, store: `BRANCH`, `WORKTREE_PATH`, `STATE_DIR`.

All subsequent NACL edits happen inside `WORKTREE_PATH`. `ORIGINAL_BRANCH` is the `--base` of the eventual PR.

### Step 6: Local edit and validate loop (max: --max-local-iterations, default 5)

Repeat until the plan is clean or the limit is reached:

**6a. Make NACL edits**

- First iteration: apply the user's requested change inside `WORKTREE_PATH`.
- Subsequent iterations: fix the errors from the previous validate run.
- Keep edits small and scoped. Summarise in one line what changed.

**6b. Run validate-local**

```
salto-cli deployment validate-local --workspace "<WORKTREE_PATH>" --target-env-id "<ENV_UUID>" --state-dir "<STATE_DIR>" --refresh-state -o summary --plan-file "<STATE_DIR>/plan.json" --allow-warnings
```

Pass `--refresh-state` **only on the first iteration** (guarantees fresh state); drop it on subsequent iterations — state doesn't change while you edit NACL locally, and re-downloading wastes time.

Read the summary from stdout:

- `changeErrors.relevant` empty → **plan is clean for your change.** Break the loop and proceed, even if `changeErrors.baseline` is non-empty — the skill is responsible only for the change it's making, not for pre-existing workspace drift.
  - Log: `Plan clean: 0 errors on my elements (<planElemIds.length> planned). Ignoring <baseline count> pre-existing baseline errors.`
  - Keep the summary values (`summary.adds/modifies/removes`, `planElemIds`, baseline counts) for the PR body in Step 9. The full plan JSON is in `<STATE_DIR>/plan.json` if you need detail.
- `changeErrors.relevant` non-empty → note each error's `elemID`, `severity`, `message`; grep `WORKTREE_PATH` for the elemID; plan a targeted fix on the next iteration.

**6c. If validate-local fails to run at all** (CLI exits non-zero with no parseable JSON): **do not push, do not commit** — print the exact error and stop. Exit code 3 *with* valid JSON is not a hard failure; it means the plan contains changeErrors — apply the `relevant` filter above.

**6d. Max iterations without clean plan**: Stop. Summarise remaining errors (mark them 🔴 per the Step 12 dot convention) and what was tried. Ask the user how to proceed. Do not push.

**6e. Security issues** — already classified by the CLI:

- `securityIssues.relevant` with `CRITICAL` or `HIGH` severity → **block the push**, surface the issue list, ask the user how to proceed. Don't auto-fix.
- `securityIssues.relevant` with `MEDIUM`/`LOW` → print a warning and continue (still push).
- `securityIssues.baseline` (any severity) → log a one-line count (`Ignoring N pre-existing security issues unrelated to this change`) and continue. Never block on baseline.

### Step 7: Build the PR body

The PR body should answer "what is this change and is it safe to deploy?". Get the changed files (stage first so brand-new files show up):

```
git -C "<WORKTREE_PATH>" add -- '*.nacl'
git -C "<WORKTREE_PATH>" diff --cached --name-status <ORIGINAL_BRANCH> -- '*.nacl'
```

Then **write the body to a file** (use your file-writing capability, not a shell heredoc — heredocs are not portable) at `<STATE_DIR>/pr-body.md`, using the Step 6 summary values:

```markdown
## What

<description>

## Plan summary

- Adds: <summary.adds>
- Modifies: <summary.modifies>
- Removes: <summary.removes>

Local `validate-local` plan is clean — zero changeErrors on the elements touched by this PR.

## Files changed

<the git diff --name-status output, in a code fence>

## Deployment

Salto will create a deployment from this PR (target env: `<ENV_NAME>`, <ENV_UUID>). Review the preview in the Salto UI before applying.
```

If baseline errors were ignored in Step 6, append: `> Note: N pre-existing baseline changeErrors on unrelated elements were ignored. They are not introduced by this PR.`

### Step 8: Ship — one CLI call (GitHub + gh available)

**Existing-deployment mode**: skip ship. Commit and push with plain git (`git -C "<WORKTREE_PATH>" add -- '*.nacl'` / `commit` / `push -u origin <BRANCH>`), then go straight to the Step 11 preview loop with the known deployment id.

**New-deployment mode**, when `GIT_PROVIDER=github` AND `GH_AVAILABLE=true`:

```
salto-cli deployment ship --workspace "<WORKTREE_PATH>" --target-env-id "<ENV_UUID>" --title "<description>" --body-file "<STATE_DIR>/pr-body.md" --base "<ORIGINAL_BRANCH>" --plan-file "<STATE_DIR>/preview-plan.json" --allow-warnings
```

This one command commits, pushes, opens the PR, creates the Salto deployment, waits for the SaaS preview, and prints the preview plan summary. From the JSON store: `BRANCH`, `PR_URL`, `DEPLOYMENT_ID` (= `deployment.id`), the deployment UI url, `planUrl`, and the plan classification.

- Exit 0 and `changeErrors.relevant` empty (or warnings only) → the SaaS preview is clean; go to Step 10b / Step 12.
- Exit 3 → Error-severity relevant changeErrors remain. The PR and deployment exist; go to the Step 11 fix loop.
- Any other failure (gh auth, push rejection, deployment-creation error) → print the error verbatim and stop; do not retry blindly. If deployment creation is the failing part, the preconditions note from the fallback path below applies (env must have `deploymentBranchingType=ENV_BASE_BRANCH`, a connected repo, and `pushSettings=AUTOMATIC`).

### Step 9: Fallback — non-GitHub host or gh unavailable

Commit and push with plain git:

```
git -C "<WORKTREE_PATH>" add -- '*.nacl'
git -C "<WORKTREE_PATH>" commit -m "<description>"
git -C "<WORKTREE_PATH>" push -u origin "<BRANCH>"
```

Then open the PR:

- **Azure DevOps with az available**: `az repos pr create --organization https://dev.azure.com/<ADO_ORG> --project <ADO_PROJECT> --repository <ADO_REPO> --source-branch <BRANCH> --target-branch <ORIGINAL_BRANCH> --title "<description>" --description "<PR body text>" --output json`; build `PR_URL` as `https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>/pullrequest/<pullRequestId>`. If an active PR already exists for the branch, recover it via `az repos pr list --source-branch <BRANCH> --status active`.
- **Host known, PR CLI unavailable**: print the compare URL (`https://github.com/<GITHUB_REPO>/compare/<ORIGINAL_BRANCH>...<BRANCH>?expand=1` or the ADO `pullrequestcreate` URL) and ask the user to open the PR and paste its URL.
- **Other hosts** (`GIT_PROVIDER=other`): tell the user to open a PR manually, then either create a deployment in the Salto UI and re-run with `--deployment-id`, or re-run with `--branch-name <BRANCH>`. Stop here.

With `PR_URL` in hand, create the deployment and run the preview:

```
salto-cli deployment create from-pull-request --pr-url "<PR_URL>" --target-env-id "<ENV_UUID>"
salto-cli deployment preview --deployment-id "<DEPLOYMENT_ID>" -o summary --plan-file "<STATE_DIR>/preview-plan.json" --allow-warnings
```

(`from-pull-request` outputs JSON by default and does not accept `--output`; take `DEPLOYMENT_ID` from its `id`. If it fails, poll `salto-cli deployment list --branch-name "<BRANCH>"` every ~5s up to 18 attempts for a webhook-created deployment; if still nothing, surface the preconditions: `deploymentBranchingType=ENV_BASE_BRANCH`, connected repo, `pushSettings=AUTOMATIC`.)

### Step 10b: Comment on the involved ticket (conditional, never blocking)

Runs only when **all three** hold: `TICKET_REF` is set (Step 2), a PR was opened (`PR_URL`), and a Salto deployment exists (`DEPLOYMENT_ID`). Otherwise skip silently.

Build the comment body from data already in hand:

```
Salto deployment opened from Claude Code

* Change: <description>
* PR: <PR_URL>
* Salto deployment: <DEPLOYMENT_ID> (target env: <ENV_NAME>)
* Plan: +<adds> / ~<modifies> / -<removes> — local validate-local clean on touched elements

Decisions made during this run:
<DECISIONS_LOG entries, one bullet each — verbatim question → answer>
```

If `DECISIONS_LOG` is empty, write `No user decisions were required — change applied as requested.` instead of an empty section.

Post it using whatever ticketing capability is available — this step is **ticketing-system-agnostic**. Try in this order:

1. **A ticketing MCP server** — discover via tool search and use its "add comment / add work-item comment" capability (Jira, Azure DevOps, or any other connected system). Match the tool to the `TICKET_REF` format detected in Step 2.
2. **A ticketing CLI** if installed and authenticated: Azure DevOps → `az boards work-item update --id <n> --discussion "<comment body>"`; Jira → the `jira` CLI.
3. **Nothing available** → print the comment body and ask the user to paste it on `<TICKET_REF>` manually.

Outcome handling: success → print `Ticket: commented on <TICKET_REF>`; failure → **do not fail or retry-loop the run** — print a one-line warning, dump the comment body for manual posting, and continue.

### Step 11: SaaS fix loop (only when relevant Error-severity changeErrors remain; max: --max-saas-iterations, default 3)

Each iteration: fix the NACLs in `WORKTREE_PATH` based on `changeErrors.relevant`, then push and re-preview (`deployment preview` pulls the new commits into the deployment and recomputes the plan — do NOT re-run `ship` here):

```
git -C "<WORKTREE_PATH>" add -- '*.nacl'
git -C "<WORKTREE_PATH>" commit -m "fix: <error summary>"
git -C "<WORKTREE_PATH>" push origin <BRANCH>
salto-cli deployment preview --deployment-id "<DEPLOYMENT_ID>" -o summary --plan-file "<STATE_DIR>/preview-plan.json" --allow-warnings
```

`changeErrors.relevant` empty → proceed to Step 12. Max iterations reached → stop, summarise remaining errors (mark them 🔴 per the Step 12 dot convention), and leave the PR open for manual inspection.

### Step 12: Finish

Print the headline:

> "SaaS preview is clean. PR is ready for review:
> **`<PR_URL>`**"

Then print a **Pipeline results** summary containing ONLY:

- **PR**: `<PR_URL>`
- **Deployment**: `<DEPLOYMENT_ID>` (+ Salto UI link)
- **Ticket**: `commented on <TICKET_REF>` / `comment failed — body printed for manual posting` / omit the line entirely when no ticket was involved
- **Branch**: `<BRANCH>` (base: `<ORIGINAL_BRANCH>`)
- **Changes made**: one line (or a short table) per element added / modified / removed
- **Change-validator status** — one dot for the final **local** `validate-local` result and one for the final **SaaS** `preview` result, judged on `changeErrors.relevant`, per the convention below.
- If baseline (pre-existing, unrelated) issues were ignored, keep the existing one-line count (`Ignored N pre-existing … issues unrelated to this change`).

**Do NOT print local-iteration or SaaS-iteration counts.**

#### Change-validator status dot convention

Judge severity from `changeErrors.relevant[].severity` in the summary output (treat `Info` as clean):

- 🟢 **Clean** — no relevant changeErrors.
- 🟡 **Warnings** — no `Error`-severity entries, but one or more `Warning`-severity relevant changeErrors (these passed only because of `--allow-warnings`). List each as `elemID — message`.
- 🔴 **Errors** — one or more `Error`-severity relevant changeErrors remain. List each as `elemID — message`.

A normal clean finish shows 🟢 local / 🟢 SaaS. 🔴 only appears via the max-iterations stop paths (Steps 6d / 11).

#### Post-deploy `git pull` — explicit, never automatic

After the deployment is applied (via the Salto UI / CI / whoever promotes it), the env's tracked branch on `origin` has the deployed changes plus any normalisation deltas from the post-deployment fetch. **Do not auto-pull.** Even in non-interactive auto-mode, print this message and stop — the user owns the moment "I'm ready to promote the deployed changes into my local workspace":

> "Once the deployment is applied in the Salto UI:
>
> 1. Run `git -C <gitRoot> pull --ff-only origin <ORIGINAL_BRANCH>` to sync the merged change into your local workspace.
> 2. Salto runs a post-deployment fetch shortly after — this can add normalisation changes (e.g. NetSuite back-propagates a new `transactionBodyCustomField` into every `transactionForm`; Zendesk strips empty `any = []` arrays from new triggers). When it completes in the Salto UI, run the same `git pull` a second time to pick those up.
>
> Skipping either pull will leave your local workspace divergent from the env and the next `/salto` run will surface that drift as noisy unrelated diffs."

Cleanup: delete `STATE_DIR` (use your file tools or `rm -rf` / `Remove-Item -Recurse` as fits the platform). Remind the user: worktree at `WORKTREE_PATH` is left for inspection; remove with `git worktree remove "<WORKTREE_PATH>"`.

## Usage examples

```
# From the workspace directory — no --workspace needed:
cd ~/path/to/your/salto-workspace
/salto "add Zendesk trigger ai_review_test that tags new tickets"

# Explicit workspace path:
/salto "rename Okta group admins to platform-admins" --workspace ~/salto-workspaces/prod

# Existing deployment (state fetched from it; preview runs against it):
/salto "fix salesforce field label" --deployment-id abc123

# Ticket-linked change — ticket auto-detected from the description (or pass --ticket):
/salto "SALTO-1234 add validation rule on Account.Website"
/salto "add validation rule on Account.Website" --ticket SALTO-1234
/salto "add validation rule on Account.Website" --ticket AB#4567   # Azure DevOps work item
```

## Notes

- `validate-local` runs without adapter credentials. Local change validators may fall back to a structural-only plan (the CLI prints a warning with the cause) — the authoritative semantic validation is the SaaS preview in Step 11.
- SaaS preview, preflight and state fetching require `SALTO_API_TOKEN`. For staging environments, also export `GRAPHQL_URL` and `SALTO_URL`.
- New-deployment mode creates the Salto deployment from the PR via `from-pull-request` (with the git host's webhook as a fallback), on **GitHub or Azure DevOps**. On any other git host, create the deployment manually in the UI and re-run with `--deployment-id`.
- On auth errors (403, "Authentication Failed"), stop immediately — do not attempt to debug credentials.
