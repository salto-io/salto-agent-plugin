#!/usr/bin/env bash
# Checks the plugin files (run it before a release; CI runs it on every PR).
#   - The manifests keep the published names and point at the repo root.
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
  got=$(jq -r "$2" "$1") || { fail "$1 is not valid JSON"; return; }
  [ "$got" = "$3" ] || fail "$1: $2 is '$got', expected '$3'"
}

version=$(jq -r .version .claude-plugin/plugin.json)
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
[ "$(cat skills/salto/VERSION)" = "$version" ] || fail "skills/salto/VERSION is '$(cat skills/salto/VERSION)', expected '$version'"

for f in SKILL.md references/salto-deploy.md references/salto-explore.md references/gemini-cli.md; do
  [ -f "skills/salto/$f" ] || fail "missing skills/salto/$f"
done

# A placeholder such as <adapter> ends the match, so "<SKILL_DIR>/adapters/<adapter>/..." checks "adapters/".
while read -r path; do
  [ -e "skills/salto/$path" ] || fail "the skill names <SKILL_DIR>/$path, which does not exist"
done < <(grep -rhoE '<SKILL_DIR>/[A-Za-z0-9_./-]+' skills/salto | sed -e 's#^<SKILL_DIR>/##' -e 's/\.*$//' | sort -u)

if grep -rnE '\{\{SKILL_ROOT\}\}|CLAUDE_PLUGIN_ROOT' skills; then
  fail "agent-specific path token in skills/ (listed above); use <SKILL_DIR>"
fi

[ "$status" = 0 ] && echo "OK: version $version; manifests and skill files are valid."
exit "$status"
