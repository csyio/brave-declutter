# brave-declutter

Turns off Brave's extra features (Rewards, Wallet, VPN, Leo AI, News, Talk, Playlist and more) using Brave's own enterprise policies, and optionally hides the buttons and new-tab items that remain afterwards.

## What it does

Brave sells a paid edition, Brave Origin, that ships without these extras. This project is a free approximation for the regular Brave build: it sets 16 enterprise policies that switch the features off, and a small optional script hides the toolbar buttons and new-tab items that stay visible.

Limits, stated plainly:

- This is not Brave Origin and is not affiliated with or endorsed by Brave Software. Origin is a separate build. This project only disables or hides features in the build you already have.
- The code of the disabled features is still in the browser. It is switched off, not removed.
- While the policies are installed, the matching switches in `brave://settings` are locked and show "managed by your organization". Remove the policies to get control back.
- Browsers can add or rename policies in new versions. If a feature comes back after an update, check `brave://policy` and open an issue.

## What gets disabled

| Feature | Policy | Value |
| --- | --- | --- |
| Brave Rewards | `BraveRewardsDisabled` | true |
| Brave Wallet | `BraveWalletDisabled` | true |
| Brave VPN | `BraveVPNDisabled` | true |
| Leo AI chat | `BraveAIChatEnabled` | false |
| Local AI models | `BraveLocalAIEnabled` | false |
| Brave News | `BraveNewsDisabled` | true |
| Brave Talk | `BraveTalkDisabled` | true |
| Playlist | `BravePlaylistEnabled` | false |
| Speedreader | `BraveSpeedreaderEnabled` | false |
| Wayback Machine prompts | `BraveWaybackMachineEnabled` | false |
| Web Discovery Project | `BraveWebDiscoveryEnabled` | false |
| Privacy-preserving product analytics (P3A) | `BraveP3AEnabled` | false |
| Daily usage ping | `BraveStatsPingEnabled` | false |
| Tor private windows | `TorDisabled` | true |
| Usage and crash metrics | `MetricsReportingEnabled` | false |
| Promotions | `PromotionsEnabled` | false |

The policy names are the same on macOS, Windows and Linux.

## Before you install

- If you use Brave Wallet, write down your recovery phrase first. If you use Brave Rewards, withdraw or claim anything pending first. The policies hide these features, and the author has not verified how existing wallet or Rewards data is treated.
- Do not use this on a computer managed by an employer or school. It sets the same policy keys their IT department may manage.

## Install

Fully quit Brave first, install, then start Brave again.

### macOS

1. Run `./macos/install.sh`, or double-click `macos/brave-declutter.mobileconfig`.
2. Open System Settings, General, Device Management.
3. Select "Brave Declutter" and click Install. macOS warns that the profile is unsigned; that is expected, the file is plain text and you can read it before installing. Download the file only from this repository, and before clicking Install check that the profile shows a single "Brave policies" custom-settings item and nothing else (no certificates, VPN or proxy payloads).
4. Quit Brave with Cmd+Q and open it again.

macOS does not let command-line tools install a profile silently, so the script only opens the file and the settings pane.

### Windows

Pick one of two variants. Both write the same 16 `REG_DWORD` values; only the registry hive differs.

- Machine-wide (recommended): `windows\brave-declutter.reg` writes under `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave` and needs an administrator account.
- Per-user: `windows\brave-declutter-user.reg` writes under `HKEY_CURRENT_USER\SOFTWARE\Policies\BraveSoftware\Brave` and may not need administrator rights, although some Windows setups protect `HKEY_CURRENT_USER\SOFTWARE\Policies` and will refuse the import. It follows Chromium's documented user-level policy location; the author has not tested it. Check `brave://policy` afterwards.

1. Double-click the `.reg` file you chose and confirm the prompts.
2. Restart Brave.

### Linux

1. Run `./linux/install.sh`. It copies `linux/brave-declutter.json` to `/etc/brave/policies/managed/brave-declutter.json` using `sudo`.
2. Restart Brave.

## Optional: hide leftover toolbar and new-tab items

Policies disable the features but do not remove every button. These preferences have no policy, so they are stored in the profile's `Preferences` file. Hidden:

- Rewards, Leo, Wallet, VPN and News buttons, and the side-panel button
- the sidebar (set to "never show")
- sponsored new-tab images, new-tab stats and Brave News on the new-tab page

### With the script

The scripts edit your own profile and need no `sudo` or administrator rights; the Python script refuses to run as root. Quit Brave completely first; the scripts refuse to run while it is open. Before changing anything, each script writes a timestamped backup (`Preferences.bak-declutter-<time>`) next to the file. If all settings are already applied, the script says so and writes nothing, so repeated runs do not create extra backups.

macOS or Linux (Python 3.9 or newer, standard library only):

```
python3 prefs/declutter-prefs.py
```

Windows without Python (PowerShell):

```
powershell -ExecutionPolicy Bypass -File prefs\declutter-prefs.ps1
```

Both target the `Default` profile. Use `--profile-dir <folder>` (Python) or `-ProfileDir <folder>` (PowerShell) for another profile.

To undo, run the same command with `--undo` (Python) or `-Undo` (PowerShell). This restores the newest backup the script made, which also reverts any other preference changes you made in Brave since then. To make that recoverable, the script first copies the current file to `Preferences.bak-declutter-preundo-<time>` and keeps it. The backup that was used is renamed to `<name>.restored`, so running undo again steps back to the next older backup. Delete the leftover backup files yourself when you no longer need them.

`--skip-running-check` / `-SkipRunningCheck` are only for the case where the running check itself fails (for example `pgrep` or `tasklist` is missing) and you are sure Brave is fully closed. Never use them on a profile Brave has open.

Flatpak and Snap builds of Brave on Linux keep their profile elsewhere and may not read `/etc/brave/policies`. Use `--profile-dir` and treat these as untested:

- Flatpak: `~/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default`
- Snap: `~/snap/brave/current/.config/BraveSoftware/Brave-Browser/Default`

Preferences paths:

- macOS: `~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Preferences`
- Linux: `~/.config/BraveSoftware/Brave-Browser/Default/Preferences`
- Windows: `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Default\Preferences`

### By hand

No script needed:

- `brave://settings/appearance`: turn off the toolbar buttons (Rewards, Leo, Wallet, VPN, News, side panel) and set the sidebar to never show.
- `brave://settings/newTab`: turn off sponsored images, stats and Brave News.

## Verify

1. Restart Brave after installing.
2. Open `brave://policy`.
3. All 16 policies from the table must be listed with level "Mandatory". If the list is empty, click "Reload policies" and restart Brave again.

## Undo

- macOS: System Settings, General, Device Management, select "Brave Declutter", click the minus button. Restart Brave.
- Windows: double-click `windows\undo-brave-declutter.reg` (administrator needed), or `windows\undo-brave-declutter-user.reg` if you installed the per-user variant. Restart Brave.
- Linux: run `./linux/uninstall.sh`, which removes the JSON file with `sudo`. Restart Brave.
- Preferences script: run it again with `--undo` / `-Undo`, or reset the switches by hand in `brave://settings`.

## Tested on

- Brave 155.1.97.56 on macOS 27.0.1.
- The Windows and Linux files follow Brave's documented policy locations and have not been tested by the author. The per-user Windows variant and Flatpak/Snap builds are also untested. Reports are welcome.
- `prefs/declutter-prefs.ps1` has not been run by the author; the Python script has.

## Why not `defaults write` on macOS

`defaults write com.brave.Browser <Policy> ...` only sets the policy at the "recommended" level, and Brave does not fully disable the features from a recommended value. A configuration profile sets the policy as mandatory, which is why this project uses one.

## License

MIT. See [LICENSE](LICENSE).
