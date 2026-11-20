# Salto Deploy (reference, loaded by the `/salto` router)

This is reference content. It is not registered as a slash command. The `/salto` router reads it when intent is classified as DEPLOY or PROMOTE, then follows the instructions below with the user's original `$ARGUMENTS`.

> [!NOTE]
>
> Invoked via: /salto "<deploy request>" [--workspace <path>] [--deployment-id <id> | --branch-name <name>] [--max-local-iterations <n>] [--max-saas-iterations <n>] [--ticket <id-or-url>]
>
> Promote: /salto "promote <deployment> to <env>" [--workspace <path>] [--deployment-id <source id> | --branch-name <source branch>]. In Promote mode `--deployment-id` / `--branch-name` name the **source** deployment; in the other modes they name the deployment to edit.

Orchestrate NACL changes from edit to SaaS-validated PR. Handles both new and existing Salto deployments, and promotes an already-deployed deployment to another environment.

All deterministic orchestration (pre-flight checks, env resolution, worktree/state-dir setup, plan classification) lives in `salto-cli` — invoke the commands and read their JSON. Do not re-implement any of it in shell; the remaining shell in this workflow is limited to `git`/`gh`/`az` one-liners that work identically on macOS, Linux and Windows.

## Three modes

**Existing deployment** — pass `--deployment-id` or `--branch-name`. The skill edits locally, validates against the target env's state (auto-fetched), then runs `deployment preview` against that existing deployment.

**New deployment** (default) — no deployment ID provided. The skill edits and validates locally first (state auto-fetched from the target env), pushes, creates a PR via the git host's CLI (`gh` for GitHub, `az repos` for Azure DevOps — or prints a create URL as a fallback), then creates a Salto deployment from the PR via `salto-cli deployment create from-pull-request`.

In both of these modes, state is downloaded directly from the target environment — no "seed deployment" is needed.

**Promote** — the user asks to promote / move / copy a deployment that is already deployed (e.g. in sandbox) to a different environment (e.g. production), with no new edit. No worktree, no NACL edits, no PR: the skill creates a Promote deployment from the source deployment via `salto-cli deployment create from-deployments`, then previews it. The target gets exactly the changes that were deployed and tested in the source env, and Salto links the two deployments. See **Promote mode** (after Step 12).

## Guardrails

- All edits happen inside a git worktree on a `salto/<task-slug>` branch (created by `salto-cli deployment prepare-worktree`). Never modify the user's working tree.
- Never push until the local plan is clean (zero relevant `changeErrors`). If `validate-local` fails for any reason, stop — do not push.
- Never force-push to any branch outside `salto/*`.
- Stop immediately on auth or credential errors. Report clearly and do not attempt to debug credentials.
- A request to promote / move / copy an already-deployed deployment to another env always uses Promote mode (`deployment create from-deployments`). Never re-apply its changes by editing NACLs on the target branch: that deploys an untested re-creation. If the source deployment can't be found, ask the user; if the promote fails, stop and report.
- Never run `sf` or `sfdx` (the Salesforce CLI), not even read-only commands like `sf org list`. Changes reach the org only through this workflow (`salto-cli` + PR + Salto deployment, or a Promote deployment; the Step 9 fallback is part of it). If the workflow can't run (preflight still fails after Step 3's env question, no linked env, no git repo), stop and report why (in Promote mode, P1 says which preflight failures to ignore). Do not deploy outside Salto (`sf project deploy`, a direct API call), even if the user asks.
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

For Azure DevOps remotes, `git.remote` is `{ "provider": "azure", "organization": "...", "project": "...", "repo": "..." }` and `git.adoPatPresent` reports whether `AZURE_DEVOPS_EXT_PAT` is set (ship needs it).

`salto-cli deployment prepare-worktree --workspace <path> --slug <task-slug> --pull` — dirty-tree check, ff-only pull, `salto/<slug>-<timestamp>` branch + worktree, temp state dir:

```json
{ "branch": "salto/<slug>-<ts>", "worktreePath": "...", "stateDir": "...", "gitRoot": "...", "baseBranch": "main", "baseCommit": "<sha>" }
```

`salto-cli deployment ship --workspace <worktree> --target-env-id <id> --title <t> --body-file <f> --base <branch> --allow-warnings` — the whole post-edit tail in one call: commit NACL changes, push, open (or reuse) the GitHub PR, create the Salto deployment from it, wait for the SaaS preview, print the plan summary. With `--allow-warnings` (always pass it — warnings are surfaced in `changeErrors.relevant` for you to report): exit 0 = preview clean or warnings only; exit 3 = Error-severity changeErrors remain (the PR and deployment still exist — continue with the fix loop). Supports GitHub (PR via `gh`) and Azure DevOps (PR via the ADO REST API — requires the `AZURE_DEVOPS_EXT_PAT` env var, a Personal Access Token with Code Read & Write scope; `preflight` warns when it's missing on an ADO remote and reports `git.adoPatPresent`). Other hosts use the granular fallback.

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

**Locating salto-cli** (do this once, before Step 1): every command below assumes `salto-cli` resolves. If it is not on PATH (common on Windows installs), locate the binary once — `where.exe salto-cli` / `Get-Command salto-cli` on Windows, `which salto-cli` elsewhere, or ask the user for the install path — and use that absolute path for **every** invocation in this workflow. PowerShell notes: executables in the current directory need the `.\` prefix, and a quoted path (e.g. containing spaces) must be invoked with the call operator: `& "C:\path\to\salto-cli.exe" deployment preflight ...`. All JSON contracts are identical regardless of how the binary is invoked (self-update included — it resolves its own location via the running process, not PATH).

**Execution discipline** (this workflow is latency-sensitive): batch independent commands into a single tool call where possible, and keep interim commentary to one short line per numbered step — every extra message between tool calls costs a full model round trip. When learning the shape of an element type, read **one** existing record of that type plus anything it references (e.g. its subsidiary) and the type definition if needed — do not read every sibling record.

**Promote requests**: if the request is to promote / move / copy an already-deployed deployment to another environment, skip Steps 1–12 and follow **Promote mode** (after Step 12) instead. If the deployment is not deployed yet, P2 only previews it (Steps 1–12 only when an edit is also asked).

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

**If the ticket *is* the task** (the request points at a ticket / work item instead of spelling out the change), fetch its content first. **Use whatever ITSM integration the user has, in this order:**

1. **A connected ITSM MCP server** — check the available tools ONCE (one tool search) for the system matching the ticket-ref format (Jira, ServiceNow, Zendesk, Linear, Azure DevOps, ...). If a matching read tool exists, use it — do not fall through to CLIs.
2. **An installed ITSM CLI** — probe in one shot for the CLIs matching the ticket format, e.g.: Jira → `acli jira workitem view <KEY>` (Atlassian CLI) or the `jira` CLI; Azure DevOps → `az boards work-item show --id <n> --organization https://dev.azure.com/<org> --output json` (needs the `azure-devops` extension; the `AZ_AVAILABLE` probe from Step 3).
3. **Neither available** → ask the user to paste the ticket content.

Remember which channel worked — Step 10b uses the same one to comment back. Read the ticket's title/description to derive the actual change, then continue the workflow. Don't infer the change from the ticket id alone.

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
- `warnings` non-empty → print them and continue. (A warning that salto-cli itself is outdated means this skill may reference commands the installed binary lacks — tell the user to run `salto-cli update` before continuing if any later command is unrecognized.)
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

For each adapter in `ADAPTER_LIST`, read its knowledge file if one is bundled with this skill: `<SKILL_DIR>/adapters/<adapter>/<adapter>.md` (`<SKILL_DIR>` is this skill's folder; see SKILL.md, Step 1). Missing adapter files are silently skipped — they are enrichment, not a requirement.

**Salesforce sub-adapters (CPQ / RLM-RCA):** for the `salesforce` adapter, also inspect the workspace data config (`fetch.data.includeObjects` in `salto.config/adapters/salesforce/salesforce.nacl`) and additionally read the matching sub-adapter file:

- `includeObjects` contains `SBQQ__` or `sbaa__` → `<SKILL_DIR>/adapters/salesforce/cpq.md`.
- `includeObjects` contains RLM objects (`ProductClassification`, `AttributeDefinition`, `RateCard`, `ProductSellingModel`, …) → `<SKILL_DIR>/adapters/salesforce/rlm.md`. (RLM is Salesforce's Revenue Cloud Advanced / **RCA** — same product, renamed; our code still calls it RLM.)

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

### Step 8: Ship — one CLI call (GitHub with gh, or Azure DevOps with AZURE_DEVOPS_EXT_PAT)

**Existing-deployment mode**: skip ship. Commit and push with plain git (`git -C "<WORKTREE_PATH>" add -- '*.nacl'` / `commit` / `push -u origin <BRANCH>`), then go straight to the Step 11 preview loop with the known deployment id.

**New-deployment mode**, when either (`GIT_PROVIDER=github` AND `GH_AVAILABLE=true`) OR (`GIT_PROVIDER=azure` AND preflight reported `git.adoPatPresent: true`). (An ADO remote **without** the PAT is not a dead end — the Step 9 fallback can open the PR through a connected Azure DevOps MCP or `az`; ship is just the faster single-call path.)

```
salto-cli deployment ship --workspace "<WORKTREE_PATH>" --target-env-id "<ENV_UUID>" --title "<description>" --body-file "<STATE_DIR>/pr-body.md" --base "<ORIGINAL_BRANCH>" --plan-file "<STATE_DIR>/preview-plan.json" --allow-warnings
```

This one command commits, pushes, opens the PR, creates the Salto deployment, waits for the SaaS preview, and prints the preview plan summary. From the JSON store: `BRANCH`, `PR_URL`, `DEPLOYMENT_ID` (= `deployment.id`), the deployment UI url, `planUrl`, and the plan classification.

- Exit 0 and `changeErrors.relevant` empty (or warnings only) → the SaaS preview is clean; go to Step 10b / Step 12.
- Exit 3 → Error-severity relevant changeErrors remain. The PR and deployment exist; go to the Step 11 fix loop.
- Any other failure (gh auth, push rejection, deployment-creation error) → print the error verbatim and stop; do not retry blindly. If deployment creation is the failing part, the preconditions note from the fallback path below applies (env must have `deploymentBranchingType=ENV_BASE_BRANCH`, a connected repo, and `pushSettings=AUTOMATIC`).

### Step 9: Fallback — unsupported host, gh unavailable, or missing ADO PAT

Commit and push with plain git:

```
git -C "<WORKTREE_PATH>" add -- '*.nacl'
git -C "<WORKTREE_PATH>" commit -m "<description>"
git -C "<WORKTREE_PATH>" push -u origin "<BRANCH>"
```

Then open the PR, trying in this order:

- **A connected git-host MCP** with a create-pull-request capability (e.g. an Azure DevOps MCP's PR tools, a GitHub MCP) — one tool search; if a matching tool exists, create the PR with it (source `<BRANCH>`, target `<ORIGINAL_BRANCH>`, the pr-body.md content as description) and take the PR URL from its response. For ADO, the URL must look like `https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>/pullrequest/<id>`.
- **Azure DevOps with az available**: `az repos pr create --organization https://dev.azure.com/<ADO_ORG> --project <ADO_PROJECT> --repository <ADO_REPO> --source-branch <BRANCH> --target-branch <ORIGINAL_BRANCH> --title "<description>" --description "<PR body text>" --output json`; build `PR_URL` as `https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>/pullrequest/<pullRequestId>`. If an active PR already exists for the branch, recover it via `az repos pr list --source-branch <BRANCH> --status active`.
- **Host known, no PR tool available**: print the compare URL (`https://github.com/<GITHUB_REPO>/compare/<ORIGINAL_BRANCH>...<BRANCH>?expand=1` or the ADO `pullrequestcreate` URL) and ask the user to open the PR and paste its URL.
- **Other hosts** (`GIT_PROVIDER=other`): the same MCP option applies if one exists for that host; otherwise tell the user to open a PR manually, then either create a deployment in the Salto UI and re-run with `--deployment-id`, or re-run with `--branch-name <BRANCH>`. Stop here if no PR can be produced.

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

Post it through **the same channel that read the ticket in Step 2** (if the ticket was fetched there). Otherwise discover one now, MCP first, in this order:

1. **A connected ITSM MCP server** — its "add comment / add work-item comment" tool for whatever system matches `TICKET_REF` (Jira, ServiceNow, Zendesk, Linear, Azure DevOps, ...). If an MCP handles it, don't touch CLIs.
2. **An installed ITSM CLI**: Jira → `acli jira workitem comment create --key <KEY> --body-file <file>` (note the `create` subcommand) or the `jira` CLI; Azure DevOps → `az boards work-item update --id <n> --discussion "<comment body>"`.
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

### Promote mode (instead of Steps 1–12)

Promote a deployment that is already deployed (the **source**, e.g. in sandbox) to another environment (the **target**, e.g. production). Salto builds the new deployment from what the source deployment actually deployed. No worktree, no NACL edits, no commit, push or PR: don't run `prepare-worktree`, `validate-local`, `ship` or `create from-pull-request` here.

**P1. Workspace and environments.** Resolve `WORKSPACE` as in Step 1, then run:

```
salto-cli deployment preflight --workspace "<WORKSPACE>"
```

Promote mode needs only these fields from it; ignore its `ok` and `failures` (they are about git and picking an env):

- `warnings` → print them (for an outdated-CLI warning, see Step 3).
- `auth.ok` not `true` (`false`, or `null` when no token is set) → stop (auth error, see Guardrails).
- `workspace.envs` → `WS_ENVS`, this workspace's envs (`name` + `id`; `id` is null in legacy workspaces).

Env ids: for an env in `WS_ENVS` with an `id`, use that id. For any other env name, run `salto-cli deployment env-info -e "<name>"` once and use its `envId`; if the name is not found or matches several envs, ask the user for the env id. Use only ids after this.

- **Target env** (`TARGET_ENV_UUID`): the env the user wants the change in. If none is named, ask.
- **Source env** (`SOURCE_ENV_UUID`): needed only when P2 looks the source up by name or recency, not when an id or branch is given. The env the user named; otherwise the `WS_ENVS` envs minus the target, if exactly one is left; otherwise unknown for now (P2 asks if it needs it).

**P2. Find the source deployment** (`SOURCE_ID`):

- `--deployment-id <id>`, `--branch-name <branch>` or a deployment id in the request → that is the source.
- Otherwise match the user's words (name, "my last one", ...) against `name`, `createdBy` and `createdAt` in these lists (most recently updated first):
  1. Source env known → its deployed deployments:

     ```
     salto-cli deployment list --env-id "<SOURCE_ENV_UUID>" --status DONE --limit 20 --no-pr-status
     ```

  2. No match there, or the source env is unknown → the target env, any status: `salto-cli deployment list --env-id "<TARGET_ENV_UUID>" --limit 20 --no-pr-status`. A match here that is not `Done` is a deployment the user wants to finish in its own env (see the hand-off below).
  3. Still no match and the source env is unknown → ask the user which env to promote from (offer the `WS_ENVS` envs other than the target). Don't search those envs and pick one yourself: which env the change was tested in matters.

  Each row has `id`, `name`, `status`, `sourceEnvId`, `targetEnvId`, `targetEnvName`, `createdBy`, `createdAt`. (`-n "<name>"` matches only the exact full name. Always pass `--env-id`: without it, `list` covers every org you can access.)
- One clear match → use it. If you matched it only by recency ("my last one"), confirm it with the user first (name, `createdBy`, `createdAt`): the list can hold teammates' deployments. Several candidates or none → show them (id, name, `createdBy`, date) and ask the user which one (and which source env, if it is unknown). Never guess, and never fall back to re-doing the change by hand.

Then read the source (the list has no `result`): `salto-cli deployment show --deployment-id "<SOURCE_ID>"` (or `--branch-name "<branch>"`). The JSON has `id`, `name`, `status`, `result` and `url`. The source deployment's env is the `targetEnvId` of its list row; when it didn't come from the list, it is the `/envs/<id>/` part of the `url` (`show` has no env field).

- `status` `Done` and `result` `SUCCESS` → promote it.
- `result` `PARTIAL_FAILURE` → only part of it was deployed: tell the user and ask before you promote it.
- `result` `FAILURE`, or `status` `Failed` → nothing was deployed: stop and tell the user.
- `status` not `Done` (not deployed yet) and its env is the target env → not a promote: the user wants that deployment deployed. Run `salto-cli deployment preview --deployment-id "<SOURCE_ID>" -o summary --allow-warnings`, report it as in P6, and tell the user to deploy it in the Salto UI. (Only if the request also asks for an edit, follow Steps 1–12 in existing-deployment mode with `--deployment-id <SOURCE_ID>`.)
- `status` not `Done` and another env → stop: there is nothing deployed to promote yet.

**Fixes.** If the user also wants the source's fixes (later deployments of the same change to the source env): `--include-all-fixes` finds them only when the source deployment came from an environment or another deployment. For a source created from a PR (every `/salto` deployment; `show`'s `description` says so) it adds nothing. Then find the fixes yourself in the source env's Done list, show them to the user, and after the user confirms, pass all the ids to `--deployment-ids` in P4. Never tell the user fixes are included when they are not.

**P3. Check the envs** (both calls in one tool call):

```
salto-cli deployment env-info -E "<TARGET_ENV_UUID>"
salto-cli deployment env-info -E "<source deployment's env id>"
```

Store `TARGET_ENV_NAME` = the target's `envName`. Both must have the same `orgId`; if not, stop and tell the user. If the target is the source deployment's env, stop: there is nothing to promote.

**P4. Create the Promote deployment:**

```
salto-cli deployment create from-deployments --deployment-ids "<SOURCE_ID>" --target-env-id "<TARGET_ENV_UUID>" --deployment-name "<name>"
```

Create it only when the user asked to promote. If they only asked what a promote would change, don't create anything: explain that the Promote deployment's preview shows it, and ask whether to create one.

- `<name>`: the name the user gave; otherwise `Promote <source name> to <TARGET_ENV_NAME>`. Drop `$`, backticks, quotes and backslashes from it, so shell quoting keeps it intact and the `-n` lookup below matches (tell the user if you changed a name they gave).
- Several source deployments: pass all their ids after `--deployment-ids`. They must all be deployed to the same env.
- `--include-all-fixes`: also include the source's fix deployments (see **Fixes** in P2 for when it works).
- `--update-if-exists`: add the source deployment(s) to an existing promotion in the target env instead of creating a new one. Use it only when the user asks for that. The CLI updates the deployment in the target env with that exact name whose status is not `Done`, `Failed` or `Selection`; make sure exactly one has that name (check with `salto-cli deployment list --env-id "<TARGET_ENV_UUID>" -n "<name>" --no-pr-status`). If none does, the CLI silently creates a new deployment.
- The command waits until the SaaS preview is ready (this can take a few minutes) and prints JSON like `{ "id": "<uuid>", "name": "...", "status": "Preview", "type": "Promote", "url": "https://app.salto.io/..." }`. Store `DEPLOYMENT_ID` = `id` and its `url`.
- **Any non-zero exit**: the CLI prints no id, but the deployment may exist anyway (e.g. its preview has conflicts). So just before `create`, note the UTC time (`date -u +%Y-%m-%dT%H:%M:%SZ`; PowerShell: `(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")`). After a failure, look for it, with that time minus one minute:

  ```
  salto-cli deployment list --env-id "<TARGET_ENV_UUID>" -n "<name>" --since "<UTC time>" --no-pr-status
  ```

  - One row → this run created it. Get its `url` with `salto-cli deployment show --deployment-id "<id>"`. Status `Preview` → store `DEPLOYMENT_ID` and go on to P5. Any other status → report its id, url and status and stop (`ConflictsResolution`: resolve the conflicts in the Salto UI; any other status: see the Salto UI).
  - Several rows → show them and ask the user.
  - No row → it was not created: print the CLI error verbatim and stop.
  - With `--update-if-exists`: only if the error is `Deployment failed to reach preview state. Status: <status>`, look up that promotion by name without `--since` and report it as updated (id, url, status). For any other error, print it word for word and say it was not updated (check it in the Salto UI).
- Never run `create` again for the same promotion: a second run makes a duplicate deployment.

**P5. Preview:**

```
salto-cli deployment preview --deployment-id "<DEPLOYMENT_ID>" -o summary --allow-warnings
```

Same summary shape as `preview` above. Exit 3 with valid JSON is a normal result, not a failure: the plan has Error changeErrors, or it is empty. An empty plan (0 adds / modifies / removes) means the target already has these changes: tell the user there is nothing to deploy. The fix loops (Steps 6 and 11) don't apply: the promoted changes are what was tested in the source env, so don't edit them. Report relevant changeErrors and let the user decide (fix in the source env and promote again, or resolve them in the Salto UI). Always go on to P6.

**P6. Finish.** Print:

- **Deployment**: `<DEPLOYMENT_ID>` (type Promote) + its `url`
- **Promoted**: `<source name>` (`<SOURCE_ID>`) → `<TARGET_ENV_NAME>`
- **Changes**: adds / modifies / removes from the preview summary (or "none: the target already has these changes")
- **Change-validator status**: one dot for the SaaS preview, with the Step 12 colors. Here 🔴 just means the preview has Error changeErrors; there is no fix loop.

Then tell the user to review and deploy it in the Salto UI. Don't deploy it yourself. After it is applied, a local checkout of the target env's tracked branch (`env-info` → `gitDetails.remoteBranchName`) needs two `git pull`s: one right away and one after Salto's post-deployment fetch (as in Step 12).

## Usage examples

```
# From the workspace directory — no --workspace needed:
cd ~/path/to/your/salto-workspace
/salto "add Zendesk trigger ai_review_test that tags new tickets"

# Explicit workspace path:
/salto "rename Okta group admins to platform-admins" --workspace ~/salto-workspaces/prod

# Existing deployment (state fetched from it; preview runs against it):
/salto "fix salesforce field label" --deployment-id abc123

# Promote an already-deployed deployment to another env (no NACL edits):
/salto "promote deployment abc123 to production"
/salto "copy the label-cleanup deployment from sandbox to prod"

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
