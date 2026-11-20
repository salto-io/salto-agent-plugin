#!/usr/bin/env bash
# Checks the plugin files (run it before a release; CI runs it on every PR).
#   - skills/salto/ is the only copy of the skill: no dist/ or meta.json (the old build).
#   - The manifests keep the published names and point at the repo root. Codex CLI reads the
#     .claude-plugin/ manifests too, so no Codex manifest may take their place.
#   - Every version matches .claude-plugin/plugin.json, the version source.
#     To release, change "version" there and in the other files this script names.
#   - The skill folder has its files, and every <SKILL_DIR>/... path it names exists.
# Requires: bash, jq.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
fail() { echo "FAIL: $*" >&2; status=1; }

# expect <file> <jq filter> <expected value>
expect() {
  local got
  got=$(jq -r "$2" "$1" 2>/dev/null) || { fail "$1 is missing or not valid JSON"; return; }
  [ "$got" = "$3" ] || fail "$1: $2 is '$got', expected '$3'"
}

for old in dist meta.json; do
  if [ -e "$old" ]; then fail "$old must not exist: skills/salto/ is the only copy of the skill (no build step)"; fi
done

# Codex CLI (0.153) reads these instead of the .claude-plugin/ files, with names and versions this script doesn't check.
# A root plugin.json (OpenAI's newer "portable" manifest) is used only when it has an agent-plugins "$schema".
for shadow in plugin.json .codex-plugin/plugin.json .agents/plugins/marketplace.json; do
  if [ -e "$shadow" ]; then fail "$shadow must not exist: Codex CLI can use it instead of .claude-plugin/ (see the comment above)"; fi
done

version=$(jq -r .version .claude-plugin/plugin.json 2>/dev/null) || { fail ".claude-plugin/plugin.json is missing or not valid JSON"; version=""; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail ".claude-plugin/plugin.json: version '$version' is not x.y.z"

expect .claude-plugin/plugin.json .name salto-cli-skills
for marketplace in .claude-plugin/marketplace.json .github/plugin/marketplace.json; do
  expect "$marketplace" .name salto-claude-plugin
  expect "$marketplace" '.plugins | length' 1
  expect "$marketplace" '.plugins[0].name' salto-cli-skills
  expect "$marketplace" '.plugins[0].source' ./
  expect "$marketplace" '.plugins[0].version' "$version"
done
expect gemini-extension.json .name salto-cli-skills
expect gemini-extension.json .version "$version"
if [ ! -f skills/salto/VERSION ] || [ "$(cat skills/salto/VERSION)" != "$version" ]; then
  fail "skills/salto/VERSION must exist and be '$version'"
fi

for f in SKILL.md references/salto-deploy.md references/salto-explore.md references/gemini-cli.md references/codex-cli.md; do
  [ -f "skills/salto/$f" ] || fail "missing skills/salto/$f"
done

# Every <SKILL_DIR>/... path must exist. A placeholder such as <adapter> matches any name, so
# "<SKILL_DIR>/adapters/<adapter>/<adapter>.md" must match at least one adapters/*/*.md file.
while read -r path; do
  case "/$path/" in
    */../*) fail "the skill names <SKILL_DIR>/$path, which leaves the skill folder ('..')"; continue;;
  esac
  pattern=$(printf '%s' "$path" | sed -e 's/<[^>]*>/*/g')
  compgen -G "skills/salto/$pattern" >/dev/null || fail "the skill names <SKILL_DIR>/$path, which does not exist"
done < <(grep -rhoE '<SKILL_DIR>/[^`[:space:])"]+' skills/salto | sed -e 's#^<SKILL_DIR>/##' -e 's/[.,;:]*$//' | sort -u)

if grep -rnE '\{\{SKILL_ROOT\}\}|CLAUDE_PLUGIN_ROOT' skills; then
  fail "agent-specific path token in skills/ (listed above); use <SKILL_DIR>"
fi

[ "$status" = 0 ] && echo "OK: version $version; manifests and skill files are valid."
exit "$status"
