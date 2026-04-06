#!/bin/bash
# portal-publish.sh — Update portal with new data and push to GitHub Pages
#
# Usage:
#   portal-publish.sh --status-update <unit> <status-line>
#   portal-publish.sh --artifact <repo-path> <local-html-file>
#   portal-publish.sh --alert <level> <unit> <title> <detail> [--source <slug>]
#   portal-publish.sh --ntfy <title> <message>
#   portal-publish.sh --clear-alerts
#
# Flags can be combined. Always commits + pushes at the end if changes exist.
# Requires: git, gh (GitHub CLI), jq, curl

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO="sjernigan14/portal"
BRANCH="main"
WORK_DIR="/tmp/portal-publish-$$"
STATUS_FILE="status.json"
NTFY_TOPIC="saj-portal-alerts"
PORTAL_URL="https://sjernigan14.github.io/portal/"
CHANGED=false

# --- Clone ---
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT
git clone --depth 1 "https://github.com/${REPO}.git" "$WORK_DIR" 2>/dev/null
cd "$WORK_DIR"

# --- Init status.json if missing ---
if [ ! -f "$STATUS_FILE" ]; then
  cat > "$STATUS_FILE" <<'INIT'
{"generated":"","alerts":[],"units":{},"artifacts":{},"ntfy":{"pendingCount":0,"lastSent":""}}
INIT
fi

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in

    --status-update)
      UNIT="$2"; STATUS_LINE="$3"; shift 3
      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      jq --arg u "$UNIT" --arg s "$STATUS_LINE" --arg t "$NOW" \
        '.units[$u] = {"status": $s, "updatedAt": $t}' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
      CHANGED=true
      echo "Updated unit status: $UNIT"
      ;;

    --artifact)
      REPO_PATH="$2"; LOCAL_FILE="$3"; shift 3
      if [ ! -f "$LOCAL_FILE" ]; then
        echo "ERROR: Local file not found: $LOCAL_FILE" >&2
        exit 1
      fi
      mkdir -p "$(dirname "$REPO_PATH")"
      cp "$LOCAL_FILE" "$REPO_PATH"
      # Update artifact metadata in status.json
      ARTIFACT_KEY="${REPO_PATH%.html}"
      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      jq --arg k "$ARTIFACT_KEY" --arg t "$NOW" \
        '.artifacts[$k].lastRun = $t | .artifacts[$k].status = "ok"' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
      CHANGED=true
      echo "Updated artifact: $REPO_PATH"
      ;;

    --alert)
      LEVEL="$2"; UNIT="$3"; TITLE="$4"; DETAIL="$5"; shift 5
      SOURCE=""
      if [[ "${1:-}" == "--source" ]]; then
        SOURCE="$2"; shift 2
      fi
      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      ALERT_ID=$(echo "${SOURCE:-$UNIT}-$(date +%Y-%m-%d)" | tr '/' '-' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
      # Remove existing alert with same ID, then prepend new one
      jq --arg id "$ALERT_ID" --arg lv "$LEVEL" --arg u "$UNIT" --arg t "$TITLE" \
         --arg d "$DETAIL" --arg src "$SOURCE" --arg ts "$NOW" \
        '(.alerts | map(select(.id != $id))) as $existing |
         .alerts = ([{"id":$id,"level":$lv,"unit":$u,"title":$t,"detail":$d,"source":$src,"timestamp":$ts}] + $existing) |
         .alerts = .alerts[:20]' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
      # Update pending count
      PENDING=$(jq '[.alerts[] | select(.level == "ACTION_NEEDED")] | length' "$STATUS_FILE")
      jq --argjson c "$PENDING" '.ntfy.pendingCount = $c' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
      CHANGED=true
      echo "Added alert: [$LEVEL] $TITLE"
      # Auto-notify for ACTION_NEEDED
      if [ "$LEVEL" = "ACTION_NEEDED" ]; then
        curl -s \
          -H "Title: $TITLE" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -H "Click: $PORTAL_URL" \
          -d "$DETAIL" \
          "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1 || true
        jq --arg t "$NOW" '.ntfy.lastSent = $t' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
        echo "Sent ntfy notification: $TITLE"
      fi
      ;;

    --ntfy)
      NTFY_TITLE="$2"; NTFY_MSG="$3"; shift 3
      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      curl -s \
        -H "Title: $NTFY_TITLE" \
        -H "Priority: high" \
        -H "Tags: warning" \
        -H "Click: $PORTAL_URL" \
        -d "$NTFY_MSG" \
        "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1 || true
      jq --arg t "$NOW" '.ntfy.lastSent = $t' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
      CHANGED=true
      echo "Sent ntfy notification: $NTFY_TITLE"
      ;;

    --activity)
      THREAD="$2"; ACTION="$3"; UNIT="$4"; shift 4
      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      jq --arg th "$THREAD" --arg a "$ACTION" --arg u "$UNIT" --arg ts "$NOW" \
        '(.activity // []) as $existing |
         .activity = ([{"timestamp":$ts,"thread":$th,"action":$a,"unit":$u}] + $existing) |
         .activity = .activity[:50]' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
      CHANGED=true
      echo "Added activity: [$THREAD] $ACTION"
      ;;

    --clear-alerts)
      shift
      jq '.alerts = [] | .ntfy.pendingCount = 0' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
      CHANGED=true
      echo "Cleared all alerts"
      ;;

    *)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

# --- Timestamp and push ---
if [ "$CHANGED" = true ]; then
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq --arg t "$NOW" '.generated = $t' "$STATUS_FILE" > tmp.$$.json && mv tmp.$$.json "$STATUS_FILE"
  git add -A
  git commit -m "Auto-update: portal data refresh $(date +%Y-%m-%d)" > /dev/null 2>&1
  git push origin "$BRANCH" > /dev/null 2>&1
  echo "Pushed to $REPO ($BRANCH)"
else
  echo "No changes to push"
fi
