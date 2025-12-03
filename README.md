# Proxmox No-Subscription Popup Remover

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Proxmox VE](https://img.shields.io/badge/Proxmox%20VE-7.x%20%7C%208.x%20%7C%209.x-orange)](https://www.proxmox.com/)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green)](https://www.gnu.org/software/bash/)
[![GitHub release](https://img.shields.io/github/v/release/Nix556/proxmox-no-popup?include_prereleases)](https://github.com/Nix556/proxmox-no-popup/releases)

Safely removes the "No valid subscription" popup in Proxmox VE without modifying core system files. Survives reboots and package upgrades.

## Features

- **Non-invasive**: Injects JS interceptor, doesn't modify `proxmoxlib.js`
- **Persistent**: Survives reboots (cron) and updates (APT hook)
- **Safe**: Creates backups before any changes
- **Self-cleaning**: Auto-removes git after install if it was auto-installed
- **Multi-node**: Deploy to cluster nodes via SSH
- **Health monitoring**: Status command with integrity checks
- **Rollback support**: Restore from any backup timestamp

## Install

```bash
git clone https://github.com/Nix556/proxmox-no-popup.git
cd proxmox-no-popup
chmod +x pve-nag-fix.sh
./pve-nag-fix.sh install
```

> **Note:** If git is not installed, the script will automatically install it and remove it after successful installation. The cloned repository is kept for other commands like uninstall, repair, status, etc.

## Uninstall

```bash
./pve-nag-fix.sh uninstall
```

## Commands

```bash
./pve-nag-fix.sh install          # install popup removal
./pve-nag-fix.sh uninstall        # remove and restore original
./pve-nag-fix.sh status           # show current state and health check
./pve-nag-fix.sh repair           # fix degraded installation
./pve-nag-fix.sh dry-run          # preview changes without applying
./pve-nag-fix.sh cleanup [N]      # remove old backups, keep N (default: 3)
./pve-nag-fix.sh rollback <ts>    # restore specific backup by timestamp
./pve-nag-fix.sh backups          # list available backups
./pve-nag-fix.sh log              # show recent log entries
./pve-nag-fix.sh multi <nodes>    # install on multiple nodes via SSH
./pve-nag-fix.sh version          # show version
./pve-nag-fix.sh --help           # show help
```

## Options

```bash
-q, --quiet    # suppress graphical output
-h, --help     # show help message
```

## Multi-node install

```bash
./pve-nag-fix.sh multi 10.0.0.1 10.0.0.2 10.0.0.3
```

Copies script to each node and runs install via SSH.

## How it works

Injects a small JS file that intercepts the popup. Doesn't touch `proxmoxlib.js`.

- Cron job restores after reboot
- APT hook restores after updates
- Backs up template before modifying
- Logs actions to `/var/log/pve-nag-fix.log`

## Files

- `/usr/local/share/pve-nag-fix/no-popup.js` - popup interceptor
- `/usr/share/pve-manager/js/no-popup.js` - symlink
- `/etc/cron.d/pve-nag-fix` - reboot persistence
- `/etc/apt/apt.conf.d/99-pve-nag-fix` - update persistence
- `/var/lib/pve-nag-fix-backups/` - template backups
- `/var/log/pve-nag-fix.log` - log file

## License

MIT
