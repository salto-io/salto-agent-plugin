#!/usr/bin/env bash
# Build per-agent skill bundles from the single source of truth in skills/salto/.
# Usage: ./generators/build.sh
#
# Emits:
#   dist/claude/   — Claude Code plugin ({{SKILL_ROOT}} -> ${CLAUDE_PLUGIN_ROOT})
#   dist/copilot/  — GitHub Copilot agent skill ({{SKILL_ROOT}} -> .)
#
# The ONLY content transform is substituting the {{SKILL_ROOT}} path token.
# Everything else is mechanical copy + per-agent manifest generation.
#
# Requires: bash, jq, perl (macOS + Linux). Not Windows.

set -euo pipefail

for tool in jq perl find; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: '$tool' is required but not found in PATH." >&2; exit 1; }
done

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/skills/salto"   # the self-contained source skill (SKILL.md + references/ + adapters/)
META="$ROOT/meta.json"     # packaging metadata (version + Claude plugin/marketplace manifests)
DIST="$ROOT/dist"

# Substitute the {{SKILL_ROOT}} token. Pattern is matched literally (\Q..\E);
# the replacement comes from $BASE via the environment so no escaping is needed.
subst() { BASE="$1" perl -pe 's/\Q{{SKILL_ROOT}}\E/$ENV{BASE}/g'; }

# Recursively copy a directory, substituting the token in every file.
copy_tree() {
  local src="$1" dest="$2" base="$3" f rel
  [ -d "$src" ] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    mkdir -p "$dest/$(dirname "$rel")"
    subst "$base" <"$f" >"$dest/$rel"
  done < <(find "$src" -type f -print0)
}

# Emit the skill bundle (SKILL.md already carries its own frontmatter) for a given base.
emit_skill() {
  local skill_dest="$1" support_dest="$2" base="$3"
  mkdir -p "$(dirname "$skill_dest")"
  subst "$base" <"$SRC/SKILL.md" >"$skill_dest"
  copy_tree "$SRC/references" "$support_dest/references" "$base"
  copy_tree "$SRC/adapters" "$support_dest/adapters" "$base"
}

# --- Claude Code plugin -----------------------------------------------------
# SKILL.md lives at skills/salto/; references/ and adapters/ live at plugin root
# (the absolute ${CLAUDE_PLUGIN_ROOT} token resolves there).
build_claude() {
  local base='${CLAUDE_PLUGIN_ROOT}' out="$DIST/claude"
  rm -rf "$out"
  mkdir -p "$out/.claude-plugin"

  jq '{
    name: .plugin.name,
    version: .version,
    description: .plugin.description,
    author: .plugin.author,
    homepage: .plugin.homepage,
    repository: .plugin.repository,
    license: .plugin.license,
    keywords: .plugin.keywords
  }' "$META" >"$out/.claude-plugin/plugin.json"

  jq '{
    name: .marketplace.name,
    owner: .marketplace.owner,
    plugins: [{
      name: .plugin.name,
      description: .marketplace.description,
      version: .version,
      source: "./"
    }]
  }' "$META" >"$out/.claude-plugin/marketplace.json"

  emit_skill "$out/skills/salto/SKILL.md" "$out" "$base"
}

# --- GitHub Copilot agent skill --------------------------------------------
# Fully self-contained skill dir; references/ and adapters/ sit beside SKILL.md.
build_copilot() {
  local base='.' out="$DIST/copilot" skilldir
  rm -rf "$out"
  skilldir="$out/.github/skills/salto"

  emit_skill "$skilldir/SKILL.md" "$skilldir" "$base"

  cat >"$out/AGENTS.md" <<'EOF'
# Salto

This repo ships the **salto** agent skill at `.github/skills/salto/SKILL.md`.

For any task against a Salto NACL workspace (deploy a change, explore/inspect state, or migrate CPQ→RLM), load that skill and follow its router.
EOF
}

# --- validation -------------------------------------------------------------
validate() {
  local problems=0 f
  if grep -rl '{{SKILL_ROOT}}' "$DIST" >/dev/null 2>&1; then
    echo "FAIL: unresolved {{SKILL_ROOT}} in:" >&2
    grep -rl '{{SKILL_ROOT}}' "$DIST" >&2
    problems=1
  fi
  local required=(
    "claude/.claude-plugin/plugin.json"
    "claude/.claude-plugin/marketplace.json"
    "claude/skills/salto/SKILL.md"
    "claude/references/salto-deploy.md"
    "claude/references/salto-explore.md"
    "claude/adapters/salesforce/cpq-to-rlm-migration.md"
    "claude/adapters/zendesk/zendesk.md"
    "copilot/.github/skills/salto/SKILL.md"
    "copilot/.github/skills/salto/references/salto-deploy.md"
    "copilot/.github/skills/salto/adapters/salesforce/cpq-to-rlm-migration.md"
    "copilot/.github/skills/salto/adapters/zendesk/zendesk.md"
    "copilot/AGENTS.md"
  )
  for f in "${required[@]}"; do
    [ -f "$DIST/$f" ] || { echo "FAIL: missing required file $f" >&2; problems=1; }
  done
  return "$problems"
}

# --- run --------------------------------------------------------------------
build_claude
build_copilot
validate

echo "Built bundles:"
echo "  claude  -> $DIST/claude ($(find "$DIST/claude" -type f | wc -l | tr -d ' ') files)"
echo "  copilot -> $DIST/copilot ($(find "$DIST/copilot" -type f | wc -l | tr -d ' ') files)"
echo "Validation: OK"
