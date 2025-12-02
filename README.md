# Proxmox No-Subscription Popup Remover

Removes the "No valid subscription" popup in Proxmox VE without modifying core files.

Works on PVE 7.x, 8.x, 9.x.

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
./install.sh status           # show current state
./install.sh dry-run          # preview changes without applying
./install.sh cleanup [N]      # remove old backups, keep N (default: 3)
./install.sh log              # show recent log entries
./install.sh multi <nodes>    # install on multiple nodes via SSH
./install.sh version          # show version
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