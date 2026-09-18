#!/bin/bash
set -euo pipefail
git add -A
git commit -m "wip: $(date '+%Y-%m-%d %H:%M')"
echo "Committed all changes as WIP"
