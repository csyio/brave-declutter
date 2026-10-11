#!/usr/bin/env bash
set -euo pipefail

sudo rm -f /etc/brave/policies/managed/brave-declutter.json
echo "Removed. Fully restart Brave to apply."
