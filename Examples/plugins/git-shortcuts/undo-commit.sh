#!/bin/bash
set -euo pipefail
git reset --soft HEAD~1
echo "Last commit undone — changes are staged"
