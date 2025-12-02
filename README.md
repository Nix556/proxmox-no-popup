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

## How it works

Injects a small JS file that intercepts the popup. Doesn't touch `proxmoxlib.js`.

- Cron job restores after reboot
- APT hook restores after updates
- Backs up template before modifying

## Files

- `/usr/local/share/pve-nag-fix/no-popup.js` - popup interceptor
- `/usr/share/pve-manager/js/no-popup.js` - symlink
- `/etc/cron.d/pve-nag-fix` - reboot persistence
- `/etc/apt/apt.conf.d/99-pve-nag-fix` - update persistence
- `/var/lib/pve-nag-fix-backups/` - template backups