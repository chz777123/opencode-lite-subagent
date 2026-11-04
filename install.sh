#!/usr/bin/env bash
# Installer for opencode-lite-subagent.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/chz777123/opencode-lite-subagent/main/install.sh | bash
#   bash install.sh --dry-run
#   bash install.sh --force
#   bash install.sh --uninstall
set -euo pipefail
umask 077

REPO_SLUG="chz777123/opencode-lite-subagent"
BRANCH="main"
RAW_BASE="${OPENCODE_LITE_SUBAGENT_RAW:-https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

FORCE=0
UNINSTALL=0
DRY_RUN=0

FILES=(
  "config/agents/scout.md|agents/scout.md"
  "config/agents/worker.md|agents/worker.md"
  "config/agents/reviewer.md|agents/reviewer.md"
  "config/agents/oracle.md|agents/oracle.md"
  "config/agents/evidence-auditor.md|agents/evidence-auditor.md"
  "config/commands/scout.md|commands/scout.md"
  "config/commands/review.md|commands/review.md"
  "config/skills/delegate/SKILL.md|skills/delegate/SKILL.md"
)

RULES_JSON='[
  { "action": "subagent", "resource": "*", "effect": "ask" },
  { "action": "shell", "resource": "git push *", "effect": "deny" },
  { "action": "shell", "resource": "git clean *", "effect": "deny" },
  { "action": "shell", "resource": "git reset --hard *", "effect": "ask" },
  { "action": "shell", "resource": "rm -rf *", "effect": "deny" }
]'

AGENTS_BEGIN='<!-- opencode-lite-subagent:begin -->'
AGENTS_END='<!-- opencode-lite-subagent:end -->'
AGENTS_BLOCK='<!-- opencode-lite-subagent:begin -->
## 子 Agent
派单前先调 `skill` 加载 `delegate`，按其门控、TaskCard 与验收规则执行。
禁止向子 agent 粘贴聊天历史或大段 diff；只传 `path:line`、`scope.write` 或文件路径。
<!-- opencode-lite-subagent:end -->'

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
opencode-lite-subagent installer

  --dry-run    print what would change, write nothing
  --force      overwrite existing files (a timestamped backup is made first)
  --uninstall  remove installed files, the AGENTS.md pointer, and the 5 rules
  -h, --help   show this help

Without --force, existing files are skipped.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $arg" ;;
  esac
done

timestamp() {
  date +%Y%m%d-%H%M%S
}

backup_file() {
  local file="$1"
  [ -e "$file" ] || return 0
  local base="${file}.bak-$(timestamp)"
  local candidate="$base"
  local n=1
  while [ -e "$candidate" ]; do
    candidate="${base}-${n}"
    n=$((n + 1))
  done
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] backup $file -> $candidate"
  else
    cp -p "$file" "$candidate"
    say "backup: $candidate"
  fi
}

fetch_to() {
  local source="$1"
  local destination="$2"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$source" ]; then
    cp "$SCRIPT_DIR/$source" "$destination"
  else
    curl -fsSL "$RAW_BASE/$source" -o "$destination"
  fi
}

install_files() {
  local entry source relative destination temporary
  for entry in "${FILES[@]}"; do
    source="${entry%%|*}"
    relative="${entry#*|}"
    destination="$CONFIG_DIR/$relative"

    if [ -e "$destination" ] && [ "$FORCE" -ne 1 ]; then
      say "skip (exists): $destination"
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      if [ -e "$destination" ]; then
        say "[dry-run] backup $destination"
      fi
      say "[dry-run] install $source -> $destination"
      continue
    fi

    if [ -e "$destination" ]; then
      backup_file "$destination"
    fi

    mkdir -p "$(dirname "$destination")"
    temporary="$(mktemp "${destination}.tmp.XXXXXX")"
    if ! fetch_to "$source" "$temporary"; then
      rm -f "$temporary"
      die "failed to fetch $source"
    fi
    chmod 644 "$temporary"
    mv "$temporary" "$destination"
    say "installed: $destination"
  done
}

uninstall_files() {
  local entry relative destination
  for entry in "${FILES[@]}"; do
    relative="${entry#*|}"
    destination="$CONFIG_DIR/$relative"

    if [ ! -e "$destination" ]; then
      say "skip (missing): $destination"
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      say "[dry-run] remove $destination"
    else
      find "$destination" -depth -delete
      say "removed: $destination"
    fi
  done

  if [ -d "$CONFIG_DIR/skills/delegate" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      say "[dry-run] remove empty directory $CONFIG_DIR/skills/delegate"
    else
      find "$CONFIG_DIR/skills/delegate" -depth -type d -empty -delete
    fi
  fi
}

install_agents_md() {
  local file="$CONFIG_DIR/AGENTS.md"

  if [ -f "$file" ] && grep -qF "$AGENTS_BEGIN" "$file"; then
    say "skip (pointer exists): $file"
    return
  fi

  if [ -f "$file" ] && grep -qF "delegate" "$file"; then
    say "skip (delegate pointer already present): $file"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] append delegate pointer to $file"
    return
  fi

  mkdir -p "$CONFIG_DIR"
  if [ -f "$file" ]; then
    backup_file "$file"
    printf '\n%s\n' "$AGENTS_BLOCK" >> "$file"
  else
    printf '%s\n' "$AGENTS_BLOCK" > "$file"
  fi
  say "updated: $file"
}

uninstall_agents_md() {
  local file="$CONFIG_DIR/AGENTS.md"

  if [ ! -f "$file" ]; then
    say "skip (missing): $file"
    return
  fi

  if ! grep -qF "$AGENTS_BEGIN" "$file"; then
    say "skip (no pointer): $file"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] remove delegate pointer from $file"
    return
  fi

  backup_file "$file"
  local temporary
  temporary="$(mktemp "${file}.tmp.XXXXXX")"
  awk -v begin="$AGENTS_BEGIN" -v end="$AGENTS_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip
  ' "$file" > "$temporary"
  mv "$temporary" "$file"
  say "updated: $file"
}

permission_file() {
  if [ -f "$CONFIG_DIR/opencode.json" ]; then
    printf '%s\n' "$CONFIG_DIR/opencode.json"
  elif [ -f "$CONFIG_DIR/opencode.jsonc" ]; then
    printf '%s\n' "$CONFIG_DIR/opencode.jsonc"
  else
    printf '%s\n' "$CONFIG_DIR/opencode.json"
  fi
}

print_rules() {
  cat >&2 <<'RULES'
Add these five rules to the "permissions" array in your OpenCode config:
[
  { "action": "subagent", "resource": "*", "effect": "ask" },
  { "action": "shell", "resource": "git push *", "effect": "deny" },
  { "action": "shell", "resource": "git clean *", "effect": "deny" },
  { "action": "shell", "resource": "git reset --hard *", "effect": "ask" },
  { "action": "shell", "resource": "rm -rf *", "effect": "deny" }
]
RULES
}

json_tool() {
  if command -v node >/dev/null 2>&1; then
    printf 'node\n'
  elif command -v jq >/dev/null 2>&1; then
    printf 'jq\n'
  elif command -v python3 >/dev/null 2>&1; then
    printf 'python3\n'
  else
    printf '\n'
  fi
}

merge_permissions() {
  local mode="$1"
  local config created
  config="$(permission_file)"
  created=0

  if [ ! -f "$config" ]; then
    if [ "$mode" = "remove" ]; then
      say "skip (missing): $config"
      return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      say "[dry-run] create $config with 5 permission rules"
      return
    fi
    mkdir -p "$CONFIG_DIR"
    printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "permissions": []\n}\n' > "$config"
    created=1
    say "created: $config"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$mode" = "add" ]; then
      say "[dry-run] ensure 5 permission rules in $config"
    else
      say "[dry-run] remove the 5 permission rules from $config"
    fi
    return
  fi

  local tool
  tool="$(json_tool)"
  if [ -z "$tool" ]; then
    print_rules
    die "node, jq and python3 are all unavailable"
  fi

  local temporary status
  temporary="$(mktemp "${config}.tmp.XXXXXX")"
  status=0

  if [ "$tool" = "node" ]; then
    node - "$config" "$RULES_JSON" "$mode" > "$temporary" <<'NODE' || status=$?
const fs = require("node:fs");

const [file, rulesJson, mode] = process.argv.slice(2);
const rules = JSON.parse(rulesJson);
const document = JSON.parse(fs.readFileSync(file, "utf8"));

if (document.permissions !== undefined && !Array.isArray(document.permissions)) {
  throw new Error("permissions must be an array");
}

const current = document.permissions ?? [];
const key = (rule) => `${rule.action}\u0000${rule.resource}\u0000${rule.effect}`;

if (mode === "add") {
  const have = new Set(current.map(key));
  const missing = rules.filter((rule) => !have.has(key(rule)));
  if (missing.length === 0) {
    process.stdout.write("__NOCHANGE__");
    process.exit(0);
  }
  document.permissions = [...current, ...missing];
} else {
  const drop = new Set(rules.map(key));
  const next = current.filter((rule) => !drop.has(key(rule)));
  if (next.length === current.length) {
    process.stdout.write("__NOCHANGE__");
    process.exit(0);
  }
  document.permissions = next;
}

process.stdout.write(`${JSON.stringify(document, null, 2)}\n`);
NODE
  elif [ "$tool" = "jq" ]; then
    jq -r --argjson rules "$RULES_JSON" --arg mode "$mode" '
      . as $document
      | (($document.permissions // [])
          | if type == "array" then . else error("permissions must be an array") end) as $current
      | ($current | map([.action, .resource, .effect])) as $have
      | ($rules | map([.action, .resource, .effect])) as $drop
      | if $mode == "add" then
          ($rules | map(select(([.action, .resource, .effect]) as $key | ($have | any(. == $key) | not)))) as $missing
          | if ($missing | length) == 0 then "__NOCHANGE__"
            else $document | .permissions = ($current + $missing)
            end
        else
          ($current | map(select(([.action, .resource, .effect]) as $key | ($drop | any(. == $key) | not)))) as $next
          | if ($next | length) == ($current | length) then "__NOCHANGE__"
            else $document | .permissions = $next
            end
        end
    ' "$config" > "$temporary" || status=$?
  else
    python3 - "$config" "$RULES_JSON" "$mode" > "$temporary" <<'PY' || status=$?
import json
import sys

file, rules_json, mode = sys.argv[1], sys.argv[2], sys.argv[3]
rules = json.loads(rules_json)
with open(file, encoding="utf-8") as handle:
    document = json.load(handle)

current = document.get("permissions", [])
if not isinstance(current, list):
    raise SystemExit("permissions must be an array")

def key(rule):
    return (rule.get("action"), rule.get("resource"), rule.get("effect"))

if mode == "add":
    have = {key(rule) for rule in current}
    missing = [rule for rule in rules if key(rule) not in have]
    if not missing:
        print("__NOCHANGE__", end="")
        raise SystemExit(0)
    document["permissions"] = current + missing
else:
    drop = {key(rule) for rule in rules}
    nxt = [rule for rule in current if key(rule) not in drop]
    if len(nxt) == len(current):
        print("__NOCHANGE__", end="")
        raise SystemExit(0)
    document["permissions"] = nxt

print(json.dumps(document, indent=2, ensure_ascii=False))
PY
  fi

  if [ "$status" -ne 0 ]; then
    rm -f "$temporary"
    print_rules
    die "failed to update $config (is it valid JSON? for JSONC, add the rules by hand)"
  fi

  if [ "$(cat "$temporary")" = "__NOCHANGE__" ]; then
    rm -f "$temporary"
    if [ "$mode" = "add" ]; then
      say "permissions unchanged: $config"
    else
      say "permissions unchanged: $config"
    fi
    return
  fi

  if [ "$created" -eq 0 ]; then
    backup_file "$config"
  fi
  mv "$temporary" "$config"
  if [ "$mode" = "add" ]; then
    say "permissions updated: $config"
  else
    say "permissions updated: $config"
  fi
}

if [ "$DRY_RUN" -eq 0 ] && [ -z "$(json_tool)" ]; then
  print_rules
  die "node, jq and python3 are all unavailable"
fi

if [ "$UNINSTALL" -eq 1 ]; then
  say "uninstalling from $CONFIG_DIR"
  uninstall_files
  uninstall_agents_md
  merge_permissions remove
  say "done"
  exit 0
fi

say "installing into $CONFIG_DIR"
install_files
install_agents_md
merge_permissions add
say "done"
