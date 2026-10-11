#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
# install sets the mode and owner explicitly; plain cp under a strict umask
# can leave a file that Brave (running as your user) cannot read.
sudo install -d -m 0755 -o root -g root /etc/brave/policies/managed
sudo install -m 0644 -o root -g root "$dir/brave-declutter.json" /etc/brave/policies/managed/brave-declutter.json
echo "Installed. Fully restart Brave, then open brave://policy to check."
