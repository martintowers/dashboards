#!/usr/bin/env bash
#
# deploy.sh — publish a static HTML dashboard to GitHub Pages.
#
# Usage:
#   ./deploy.sh [--encrypt | -p <password>] <dashboard-name> <path-to-html-file>
#
# Examples:
#   ./deploy.sh sales-q3 ~/Downloads/sales.html                 # public
#   ./deploy.sh -p 'hunter2' sales-q3 ~/Downloads/sales.html    # password-protected
#   STATICRYPT_PASSWORD='hunter2' ./deploy.sh --encrypt sales-q3 ~/Downloads/sales.html
#
# Password protection uses StatiCrypt: the dashboard is AES-encrypted *before*
# it is committed, so the public repo only ever holds ciphertext. Visitors are
# prompted for the passphrase and the page decrypts in their browser. The
# plaintext source file is never copied into the repo.
#
# What it does:
#   1. Places your HTML into <dashboard-name>/index.html (encrypting it if asked)
#   2. Regenerates the root index.html listing every dashboard
#   3. Commits and pushes to the main branch
#   4. Waits for the GitHub Pages deployment to go live
#   5. Prints the public URL
#
set -euo pipefail

# ---- config -----------------------------------------------------------------
GH_USER="martintowers"
REPO="dashboards"
BASE_URL="https://${GH_USER}.github.io/${REPO}"
# Run everything relative to this script's own directory.
cd "$(dirname "$0")"

# ---- args -------------------------------------------------------------------
PASSWORD=""
ENCRYPT=0
POSITIONAL=()
USAGE="Usage: ./deploy.sh [--encrypt | -p <password>] <dashboard-name> <path-to-html-file>"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--password) PASSWORD="${2:-}"; ENCRYPT=1; shift 2 ;;
    --encrypt)     ENCRYPT=1; shift ;;
    -h|--help)     echo "$USAGE"; exit 0 ;;
    -*)            echo "Unknown option: $1" >&2; echo "$USAGE" >&2; exit 1 ;;
    *)             POSITIONAL+=("$1"); shift ;;
  esac
done

if [ "${#POSITIONAL[@]}" -ne 2 ]; then
  echo "$USAGE" >&2
  exit 1
fi

NAME="${POSITIONAL[0]}"
SRC="${POSITIONAL[1]}"

# dashboard name must be URL/folder safe
if ! echo "$NAME" | grep -Eq '^[a-zA-Z0-9._-]+$'; then
  echo "Error: dashboard name '$NAME' must contain only letters, numbers, dots, dashes or underscores." >&2
  exit 1
fi

if [ ! -f "$SRC" ]; then
  echo "Error: file not found: $SRC" >&2
  exit 1
fi

# ---- 1. place (and optionally encrypt) the file ----------------------------
mkdir -p "$NAME"
DEST="$NAME/index.html"

if [ "$ENCRYPT" -eq 1 ]; then
  # Encrypt with StatiCrypt. Only ciphertext is written into the repo; the
  # plaintext source ($SRC) is never copied in, so it stays private.
  tmp="$(mktemp -d)"
  cp "$SRC" "$tmp/index.html"
  pw_args=()
  [ -n "$PASSWORD" ] && pw_args=(-p "$PASSWORD")
  # With no -p, StatiCrypt uses $STATICRYPT_PASSWORD or prompts interactively.
  npx --yes staticrypt@3 "$tmp/index.html" ${pw_args[@]+"${pw_args[@]}"} -d "$NAME" -c false --short
  rm -rf "$tmp"
  echo "🔒 Encrypted $SRC -> $DEST (password-protected)"
else
  # Skip the copy if source and destination are the same file (in-place redeploy).
  if [ "$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")" = "$(cd "$(dirname "$DEST")" && pwd)/$(basename "$DEST")" ]; then
    echo "✓ Source is already $DEST (in-place redeploy)"
  else
    cp "$SRC" "$DEST"
    echo "✓ Copied $SRC -> $DEST"
  fi
fi

# ---- 2. regenerate the root index ------------------------------------------
generate_index() {
  {
    cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Dashboards</title>
  <style>
    :root { --bg:#0f172a; --card:#1e293b; --accent:#38bdf8; --text:#e2e8f0; --muted:#94a3b8; }
    * { box-sizing:border-box; margin:0; padding:0; }
    body { font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
           background:linear-gradient(135deg,var(--bg),#020617); color:var(--text);
           min-height:100vh; padding:3rem 1.5rem; }
    .wrap { max-width:760px; margin:0 auto; }
    h1 { font-size:2rem; margin-bottom:0.25rem; }
    p.sub { color:var(--muted); margin-bottom:2rem; }
    ul { list-style:none; display:grid; gap:0.75rem; }
    li a { display:flex; align-items:center; justify-content:space-between;
           background:var(--card); border:1px solid #334155; border-radius:12px;
           padding:1.1rem 1.25rem; color:var(--text); text-decoration:none;
           transition:border-color .15s, transform .15s; }
    li a:hover { border-color:var(--accent); transform:translateY(-2px); }
    li a .name { font-weight:600; }
    li a .arrow { color:var(--accent); }
    .empty { color:var(--muted); background:var(--card); border:1px dashed #334155;
             border-radius:12px; padding:1.5rem; text-align:center; }
    footer { margin-top:2.5rem; font-size:0.8rem; color:var(--muted); }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Dashboards</h1>
    <p class="sub">Static dashboards published to GitHub Pages.</p>
    <ul>
HEAD

    local found=0
    for dir in */; do
      d="${dir%/}"
      [ -f "$d/index.html" ] || continue
      found=1
      # Mark password-protected (StatiCrypt-encrypted) dashboards with a lock.
      label="$d"
      if grep -q "staticrypt" "$d/index.html" 2>/dev/null; then
        label="$d 🔒"
      fi
      printf '      <li><a href="%s/"><span class="name">%s</span><span class="arrow">&rarr;</span></a></li>\n' "$d" "$label"
    done
    if [ "$found" -eq 0 ]; then
      printf '      <li class="empty">No dashboards yet.</li>\n'
    fi

    cat <<'TAIL'
    </ul>
    <footer>Published with deploy.sh &middot; updated automatically on each deploy.</footer>
  </div>
</body>
</html>
TAIL
  } > index.html
}

generate_index
echo "✓ Regenerated root index.html"

# ---- 3. commit & push -------------------------------------------------------
git add -A
if git diff --cached --quiet; then
  echo "No changes to commit (content identical to last deploy)."
else
  git commit -q -m "Deploy dashboard: $NAME"
  echo "✓ Committed"
fi
git push -q origin main
echo "✓ Pushed to origin/main"

# ---- 4. wait for Pages to go live ------------------------------------------
URL="${BASE_URL}/${NAME}/"
echo "Waiting for GitHub Pages to publish ${URL} ..."

# Prefer watching the actual Pages deployment via gh; fall back to polling URL.
if command -v gh >/dev/null 2>&1; then
  for i in $(seq 1 30); do
    status=$(gh api "repos/${GH_USER}/${REPO}/pages/builds/latest" --jq .status 2>/dev/null || echo "")
    if [ "$status" = "built" ]; then
      break
    fi
    sleep 5
  done
fi

# Poll the live URL until it serves a 200 (Pages CDN can lag a few seconds).
live=0
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$URL" || echo "000")
  if [ "$code" = "200" ]; then
    live=1
    break
  fi
  sleep 5
done

echo ""
if [ "$live" -eq 1 ]; then
  echo "✅ Live: ${URL}"
else
  echo "⚠️  Pushed, but the URL didn't return 200 yet. GitHub Pages can take 1-2 minutes on first publish."
  echo "    Check shortly: ${URL}"
fi
echo "   Index: ${BASE_URL}/"
