#!/bin/bash
set -euo pipefail
MAIN=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
git branch --merged "$MAIN" | grep -v "^\*" | grep -v "$MAIN" | xargs -r git branch -d
echo "Merged branches cleaned up"
