#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"

# macOS does not allow installing a profile silently, so this only opens
# the file and the settings pane. You confirm the install yourself.
open "$dir/brave-declutter.mobileconfig"
open "x-apple.systempreferences:com.apple.Profiles-Settings.extension"

cat <<'MSG'

Finish in System Settings:
  1. General > Device Management
  2. Select "Brave Declutter" (macOS says it is unsigned; that is expected)
  3. Click Install and confirm
  4. Quit Brave completely (Cmd+Q) and reopen it
  5. Open brave://policy and check that the policies show level "Mandatory"

To remove it later: same pane, select "Brave Declutter", click the minus button.
MSG
