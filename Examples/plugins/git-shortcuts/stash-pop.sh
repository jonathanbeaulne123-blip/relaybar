#!/bin/bash
set -euo pipefail
git stash pop
echo "Stash restored successfully"
