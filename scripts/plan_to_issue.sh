#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <plan.md> [--label <label>]..."
  exit 1
fi

PLAN_PATH="$1"
shift

if [[ ! -f "$PLAN_PATH" ]]; then
  echo "Plan file not found: $PLAN_PATH"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install from https://cli.github.com/ and run: gh auth login"
  exit 1
fi

LABELS=("plan")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      LABELS+=("${2:-}")
      shift 2
      ;;
    *)
      echo "Unknown arg: $1"
      exit 1
      ;;
  esac
done

TITLE="$(grep -m1 -E '^# ' "$PLAN_PATH" | sed 's/^# //')"
if [[ -z "${TITLE:-}" ]]; then
  TITLE="$(basename "$PLAN_PATH" .md)"
fi

LABEL_ARG="$(IFS=,; echo "${LABELS[*]}")"

gh issue create \
  --title "$TITLE" \
  --body-file "$PLAN_PATH" \
  --label "$LABEL_ARG"

