#!/bin/bash
# Proxmox VE subscription popup remover
# Injects JS to suppress popup - doesn't modify core files
# Usage: ./install.sh [install|uninstall|status]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

JS_SOURCE="/usr/local/share/pve-nag-fix/no-popup.js"
JS_LINK="/usr/share/pve-manager/js/no-popup.js"
TEMPLATE="/usr/share/pve-manager/index.html.tpl"
CRON_FILE="/etc/cron.d/pve-nag-fix"
BACKUP_DIR="/var/lib/pve-nag-fix-backups"
SCRIPT_TAG='<script src="/pve2/js/no-popup.js"></script>'

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: run as root${NC}"
        exit 1
    fi
}

check_proxmox() {
    # verify this is actually a proxmox server
    if ! command -v pveversion &>/dev/null; then
        echo -e "${RED}Error: pveversion not found - is this a Proxmox server?${NC}"
        exit 1
    fi
    
    if [[ ! -f "$TEMPLATE" ]]; then
        echo -e "${RED}Error: template not found at $TEMPLATE${NC}"
        exit 1
    fi
    
    if [[ ! -d "/usr/share/pve-manager/js" ]]; then
        echo -e "${RED}Error: pve-manager js directory not found${NC}"
        exit 1
    fi
}

verify_backup() {
    # make sure backup was created before proceeding
    local backup_file="$1"
    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}Error: backup failed, aborting${NC}"
        exit 1
    fi
    
    # verify backup has content
    if [[ ! -s "$backup_file" ]]; then
        echo -e "${RED}Error: backup file is empty, aborting${NC}"
        rm -f "$backup_file"
        exit 1
    fi
}

already_installed() {
    # check if already installed to prevent double-patching
    if grep -q "no-popup.js" "$TEMPLATE" 2>/dev/null; then
        return 0
    fi
    return 1
}

install() {
    check_root
    check_proxmox
    
    # prevent double install
    if already_installed; then
        echo -e "${YELLOW}Already installed. Run 'uninstall' first if you want to reinstall.${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}Installing...${NC}"
    
    mkdir -p /usr/local/share/pve-nag-fix
    mkdir -p "$BACKUP_DIR"
    
    # backup template
    BACKUP_FILE="$BACKUP_DIR/index.html.tpl.$(date +%Y%m%d%H%M%S).bak"
    if [[ -f "$TEMPLATE" ]]; then
        cp "$TEMPLATE" "$BACKUP_FILE"
        verify_backup "$BACKUP_FILE"
        echo -e "${GREEN}Backed up template to $BACKUP_FILE${NC}"
    fi
    
    # create js file - waits for Ext to load
    cat > "$JS_SOURCE" << 'EOF'
(function() {
    function patchPopup() {
        if (typeof Ext === 'undefined' || typeof Ext.Msg === 'undefined') {
            setTimeout(patchPopup, 100);
            return;
        }
        var origShow = Ext.Msg.show;
        Ext.Msg.show = function(c) {
            if (c && c.title && c.title.indexOf('No valid subscription') !== -1) return;
            return origShow.apply(this, arguments);
        };
    }
    patchPopup();
})();
EOF
    chmod 644 "$JS_SOURCE"
    
    # verify js was created
    if [[ ! -f "$JS_SOURCE" ]]; then
        echo -e "${RED}Error: failed to create JS file${NC}"
        exit 1
    fi
    
    # symlink
    ln -sf "$JS_SOURCE" "$JS_LINK"
    
    # add to template only if not already there
    if ! grep -q "no-popup.js" "$TEMPLATE" 2>/dev/null; then
        if grep -q "</head>" "$TEMPLATE"; then
            sed -i "s|</head>|$SCRIPT_TAG\n</head>|" "$TEMPLATE"
            echo -e "${GREEN}Added script to template${NC}"
        else
            echo -e "${RED}Error: couldn't find </head> in template${NC}"
            exit 1
        fi
    fi
    
    # verify template was modified
    if ! grep -q "no-popup.js" "$TEMPLATE"; then
        echo -e "${RED}Error: template modification failed${NC}"
        # restore backup
        cp "$BACKUP_FILE" "$TEMPLATE"
        echo -e "${YELLOW}Restored template from backup${NC}"
        exit 1
    fi
    
    # cron for reboot persistence
    cat > "$CRON_FILE" << EOF
@reboot root sleep 30 && ln -sf $JS_SOURCE $JS_LINK 2>/dev/null
EOF
    chmod 644 "$CRON_FILE"
    
    # apt hook for update persistence
    cat > /etc/apt/apt.conf.d/99-pve-nag-fix << EOF
DPkg::Post-Invoke { "[ -f $JS_SOURCE ] && ln -sf $JS_SOURCE $JS_LINK 2>/dev/null || true"; };
EOF
    
    # only restart if pveproxy is running
    if systemctl is-active --quiet pveproxy 2>/dev/null; then
        systemctl restart pveproxy
    fi
    
    echo -e "${GREEN}Done. Refresh browser.${NC}"
    echo ""
    echo "Backup location: $BACKUP_FILE"
    echo "To undo: ./install.sh uninstall"
}

uninstall() {
    check_root
    echo -e "${YELLOW}Uninstalling...${NC}"
    
    # restore template from backup first (safest)
    if [[ -d "$BACKUP_DIR" ]]; then
        LATEST=$(ls -t "$BACKUP_DIR"/index.html.tpl.*.bak 2>/dev/null | head -1)
        if [[ -f "$LATEST" ]]; then
            cp "$LATEST" "$TEMPLATE"
            echo -e "${GREEN}Restored template from backup${NC}"
        else
            # no backup, try to remove line manually
            if [[ -f "$TEMPLATE" ]]; then
                sed -i '/no-popup\.js/d' "$TEMPLATE" 2>/dev/null
                echo -e "${YELLOW}Removed script tag (no backup found)${NC}"
            fi
        fi
    fi
    
    # remove our files (safe - these are only ours)
    rm -f "$JS_LINK"
    rm -rf /usr/local/share/pve-nag-fix
    rm -f "$CRON_FILE"
    rm -f /etc/apt/apt.conf.d/99-pve-nag-fix
    
    # only restart if pveproxy exists and is running
    if systemctl is-active --quiet pveproxy 2>/dev/null; then
        systemctl restart pveproxy
    fi
    
    echo -e "${GREEN}Done. Refresh browser.${NC}"
}

status() {
    echo -e "${YELLOW}Status:${NC}"
    
    # show pve version first
    if command -v pveversion &>/dev/null; then
        pveversion
        echo ""
    fi
    
    [[ -f "$JS_SOURCE" ]] && echo -e "${GREEN}JS file: installed${NC}" || echo -e "${RED}JS file: missing${NC}"
    [[ -L "$JS_LINK" ]] && echo -e "${GREEN}Symlink: ok${NC}" || echo -e "${RED}Symlink: missing${NC}"
    grep -q "no-popup.js" "$TEMPLATE" 2>/dev/null && echo -e "${GREEN}Template: patched${NC}" || echo -e "${RED}Template: not patched${NC}"
    [[ -f "$CRON_FILE" ]] && echo -e "${GREEN}Cron: installed${NC}" || echo -e "${RED}Cron: missing${NC}"
    [[ -f "/etc/apt/apt.conf.d/99-pve-nag-fix" ]] && echo -e "${GREEN}APT hook: installed${NC}" || echo -e "${RED}APT hook: missing${NC}"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        COUNT=$(ls -1 "$BACKUP_DIR"/*.bak 2>/dev/null | wc -l)
        echo ""
        echo "Backups: $COUNT file(s) in $BACKUP_DIR"
        ls -la "$BACKUP_DIR"/*.bak 2>/dev/null | tail -3
    fi
}

# dry-run to show what would happen without making changes
dry_run() {
    echo -e "${YELLOW}Dry run - no changes will be made${NC}"
    echo ""
    
    check_root
    check_proxmox
    
    if already_installed; then
        echo "Status: Already installed"
    else
        echo "Status: Not installed"
    fi
    
    echo ""
    echo "Would create:"
    echo "  - $JS_SOURCE"
    echo "  - $JS_LINK (symlink)"
    echo "  - $CRON_FILE"
    echo "  - /etc/apt/apt.conf.d/99-pve-nag-fix"
    echo ""
    echo "Would modify:"
    echo "  - $TEMPLATE (add script tag)"
    echo ""
    echo "Would backup:"
    echo "  - $TEMPLATE -> $BACKUP_DIR/"
}

case "${1:-}" in
    install) install ;;
    uninstall|remove) uninstall ;;
    status) status ;;
    dry-run|--dry-run) dry_run ;;
    *)
        echo "Proxmox subscription popup remover"
        echo ""
        echo "Usage: $0 {install|uninstall|status|dry-run}"
        echo ""
        echo "  install   - install popup removal"
        echo "  uninstall - remove and restore original"
        echo "  status    - show current state"
        echo "  dry-run   - show what would happen without making changes"
        ;;
esac