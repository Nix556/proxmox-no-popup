# Proxmox No-Subscription Popup Remover

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Proxmox VE](https://img.shields.io/badge/Proxmox%20VE-7.x%20%7C%208.x%20%7C%209.x-orange)](https://www.proxmox.com/)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green)](https://www.gnu.org/software/bash/)
[![GitHub release](https://img.shields.io/github/v/release/Nix556/proxmox-no-popup?include_prereleases)](https://github.com/Nix556/proxmox-no-popup/releases)

Safely removes the "No valid subscription" popup in Proxmox VE without modifying core system files. Survives reboots and package upgrades.

## Install

```bash
chmod +x install.sh
./install.sh install
```

## Uninstall

```bash
./install.sh uninstall
```

## Commands

```bash
./install.sh install          # install popup removal
./install.sh uninstall        # remove and restore original
./install.sh status           # show current state and version check
./install.sh dry-run          # preview changes without applying
./install.sh cleanup [N]      # remove old backups, keep N (default: 3)
./install.sh rollback <ts>    # restore specific backup by timestamp
./install.sh backups          # list available backups
./install.sh log              # show recent log entries
./install.sh multi <nodes>    # install on multiple nodes via SSH
./install.sh version          # show version
./install.sh --help           # show help
```

## Options

```bash
-q, --quiet    # suppress graphical output
-h, --help     # show help message
```

## Multi-node install

```bash
./install.sh multi 10.0.0.1 10.0.0.2 10.0.0.3
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