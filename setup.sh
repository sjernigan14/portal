#!/bin/bash
# Portal Setup Script — Run from Mac Terminal
# This creates the GitHub repo and pushes the portal

set -e

echo "=== SAJ Consulting Portal Setup ==="

# Check gh is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI not found. Installing..."
    brew install gh
fi

# Check auth
if ! gh auth status &> /dev/null 2>&1; then
    echo "Not logged into GitHub. Logging in..."
    gh auth login
fi

# Navigate to portal directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Working directory: $(pwd)"

# Create repo if it doesn't exist
if gh repo view sjernigan14/portal &> /dev/null 2>&1; then
    echo "Repo sjernigan14/portal already exists"
else
    echo "Creating private repo sjernigan14/portal..."
    gh repo create portal --private --description "Private portal for dashboards, tools, and artifacts — SAJ Consulting"
fi

# Init git if needed
if [ ! -d ".git" ]; then
    git init
    git remote add origin https://github.com/sjernigan14/portal.git
fi

# Add all files
git add -A
git commit -m "Initial portal build — landing page + folder structure

Business units: Crawford Hospitality, MEGA, Patron Properties, NSH/SAJ, Personal
Password gate (hash-based, no plaintext in source)
Dark theme, mobile responsive
Artifact cards with links to GitHub Pages sites

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

# Push
git branch -M main
git push -u origin main

# Enable GitHub Pages
echo ""
echo "Enabling GitHub Pages..."
gh api repos/sjernigan14/portal/pages -X POST -f "source[branch]=main" -f "source[path]=/" 2>/dev/null || echo "Pages may already be enabled or needs manual setup"

echo ""
echo "=== DONE ==="
echo "Portal URL: https://sjernigan14.github.io/portal/"
echo ""
echo "To set a password, open the site in Chrome, open Console (Cmd+Option+J), and run:"
echo "  crypto.subtle.digest('SHA-256', new TextEncoder().encode('YOUR_PASSWORD')).then(h => console.log(Array.from(new Uint8Array(h)).map(b => b.toString(16).padStart(2,'0')).join('')))"
echo "Then paste the hash into index.html line: var HASH = '';"
echo "Commit and push again."
