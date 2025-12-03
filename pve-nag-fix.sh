#!/bin/bash
# Proxmox VE subscription popup remover v1.4.0
# Injects JS to suppress popup - doesn't modify core files

set -euo pipefail

VERSION="1.4.0"
VERSION_FILE="/usr/local/share/pve-nag-fix/.version"

# cleanup on error
trap 'log "Script interrupted or failed"' ERR

# colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# symbols
CHECK="${GREEN}[OK]${NC}"
CROSS="${RED}[FAIL]${NC}"
ARROW="${CYAN}>>>${NC}"
DOT="${DIM}...${NC}"

JS_SOURCE="/usr/local/share/pve-nag-fix/no-popup.js"
JS_LINK="/usr/share/pve-manager/js/no-popup.js"
TEMPLATE="/usr/share/pve-manager/index.html.tpl"
CRON_FILE="/etc/cron.d/pve-nag-fix"
BACKUP_DIR="/var/lib/pve-nag-fix-backups"
LOG_FILE="/var/log/pve-nag-fix.log"
SCRIPT_TAG='<script src="/pve2/js/no-popup.js"></script>'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_INSTALLED_BY_SCRIPT=false

# header
header() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ____                                        _   _         ____                        "
    echo " |  _ \ _ __ _____  ___ __ ___   _____  __   | \ | | ___   |  _ \ ___  _ __  _   _ _ __  "
    echo " | |_) | '__/ _ \ \/ / '_ \` _ \ / _ \ \/ /   |  \| |/ _ \  | |_) / _ \| '_ \| | | | '_ \ "
    echo " |  __/| | | (_) >  <| | | | | | (_) >  <    | |\  | (_) | |  __/ (_) | |_) | |_| | |_) |"
    echo " |_|   |_|  \___/_/\_\_| |_| |_|\___/_/\_\   |_| \_|\___/  |_|   \___/| .__/ \__,_| .__/ "
    echo "                                                                      |_|        |_|    "
    echo -e "${NC}"
    echo -e "${DIM}  Subscription Popup Remover v${VERSION}${NC}"
    echo ""
}

# step display
step() {
    echo -ne "  ${ARROW} $1 ${DOT} "
}

step_ok() {
    echo -e "\r  ${CHECK} $1          "
}

step_fail() {
    echo -e "\r  ${CROSS} $1          "
}

# progress bar
progress() {
    local duration=${1:-1}
    local steps=20
    local delay
    delay=$(awk "BEGIN {printf \"%.3f\", $duration / $steps}" 2>/dev/null || echo "0.05")
    
    echo -ne "  ["
    for ((i=0; i<steps; i++)); do
        echo -ne "${GREEN}#${NC}"
        sleep "$delay" 2>/dev/null || true
    done
    echo -e "] ${GREEN}Done${NC}"
}

# logging
log() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        step_fail "Root check"
        echo -e "  ${RED}Error: run as root${NC}"
        exit 1
    fi
}

ensure_git() {
    if ! command -v git &>/dev/null; then
        step "Installing git"
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq git >/dev/null 2>&1
        if command -v git &>/dev/null; then
            GIT_INSTALLED_BY_SCRIPT=true
            step_ok "Installing git"
        else
            step_fail "Installing git"
            echo -e "  ${RED}Error: failed to install git${NC}"
            exit 1
        fi
    fi
}

cleanup_after_install() {
    # remove git if we installed it (keep the repo for other commands)
    if $GIT_INSTALLED_BY_SCRIPT; then
        step "Removing git (auto-installed)"
        apt-get remove -y -qq git >/dev/null 2>&1 || true
        apt-get autoremove -y -qq >/dev/null 2>&1 || true
        step_ok "Removing git (auto-installed)"
        log "Removed git (was installed by script)"
    fi
}

check_proxmox() {
    step "Checking Proxmox"
    
    if ! command -v pveversion &>/dev/null; then
        step_fail "Checking Proxmox"
        echo -e "  ${RED}Error: not a Proxmox server${NC}"
        exit 1
    fi
    if [[ ! -f "$TEMPLATE" ]]; then
        step_fail "Checking Proxmox"
        echo -e "  ${RED}Error: template not found${NC}"
        exit 1
    fi
    
    step_ok "Checking Proxmox"
}

verify_backup() {
    local backup_file="$1"
    if [[ ! -f "$backup_file" ]] || [[ ! -s "$backup_file" ]]; then
        step_fail "Creating backup"
        log "ERROR: backup verification failed"
        rm -f "$backup_file" 2>/dev/null
        exit 1
    fi
}

already_installed() {
    grep -q "no-popup.js" "$TEMPLATE" 2>/dev/null
}

verify_integrity() {
    # verify all components are properly installed
    [[ -f "$JS_SOURCE" ]] && \
    [[ -L "$JS_LINK" ]] && \
    [[ -f "$CRON_FILE" ]] && \
    grep -q "no-popup.js" "$TEMPLATE" 2>/dev/null
}

install() {
    header
    echo -e "  ${BOLD}Installing...${NC}"
    echo ""
    
    check_root
    ensure_git
    check_proxmox
    
    if already_installed; then
        echo ""
        echo -e "  ${YELLOW}Already installed.${NC}"
        echo -e "  Run ${BOLD}./pve-nag-fix.sh uninstall${NC} first to reinstall."
        echo ""
        exit 0
    fi
    
    log "Starting install v$VERSION"
    
    # create directories
    step "Creating directories"
    mkdir -p /usr/local/share/pve-nag-fix
    mkdir -p "$BACKUP_DIR"
    step_ok "Creating directories"
    progress 0.3
    
    # check disk space (need at least 1MB free)
    local free_space
    free_space=$(df -k "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ "$free_space" -lt 1024 ]]; then
        step_fail "Disk space check"
        echo -e "  ${RED}Error: insufficient disk space${NC}"
        exit 1
    fi
    
    # backup template
    step "Backing up template"
    BACKUP_FILE="$BACKUP_DIR/index.html.tpl.$(date +%Y%m%d%H%M%S).bak"
    cp "$TEMPLATE" "$BACKUP_FILE"
    verify_backup "$BACKUP_FILE"
    log "Backup created: $BACKUP_FILE"
    step_ok "Backing up template"
    
    # save version
    echo "$VERSION" > "$VERSION_FILE"
    
    # create js file
    step "Creating JS interceptor"
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
    
    if [[ ! -f "$JS_SOURCE" ]]; then
        step_fail "Creating JS interceptor"
        exit 1
    fi
    step_ok "Creating JS interceptor"
    progress 0.5
    
    # symlink
    step "Creating symlink"
    ln -sf "$JS_SOURCE" "$JS_LINK"
    step_ok "Creating symlink"
    
    # patch template
    step "Patching template"
    if ! grep -q "no-popup.js" "$TEMPLATE" 2>/dev/null; then
        if grep -q "</head>" "$TEMPLATE"; then
            sed -i "s|</head>|$SCRIPT_TAG\n</head>|" "$TEMPLATE"
        else
            step_fail "Patching template"
            cp "$BACKUP_FILE" "$TEMPLATE"
            exit 1
        fi
    fi
    
    if ! grep -q "no-popup.js" "$TEMPLATE"; then
        step_fail "Patching template"
        cp "$BACKUP_FILE" "$TEMPLATE"
        exit 1
    fi
    step_ok "Patching template"
    progress 0.4
    
    # cron job
    step "Setting up cron"
    cat > "$CRON_FILE" << EOF
@reboot root sleep 30 && ln -sf $JS_SOURCE $JS_LINK 2>/dev/null
EOF
    chmod 644 "$CRON_FILE"
    step_ok "Setting up cron"
    
    # apt hook
    step "Setting up APT hook"
    cat > /etc/apt/apt.conf.d/99-pve-nag-fix << EOF
DPkg::Post-Invoke { "[ -f $JS_SOURCE ] && ln -sf $JS_SOURCE $JS_LINK 2>/dev/null || true"; };
EOF
    step_ok "Setting up APT hook"
    progress 0.3
    
    # restart pveproxy
    step "Restarting pveproxy"
    if systemctl is-active --quiet pveproxy 2>/dev/null; then
        systemctl restart pveproxy
    fi
    step_ok "Restarting pveproxy"
    progress 0.5
    
    # verify installation
    step "Verifying installation"
    if verify_integrity; then
        step_ok "Verifying installation"
        log "Install completed successfully - all components verified"
    else
        step_fail "Verifying installation"
        log "WARNING: Install completed but verification failed"
    fi
    
    # cleanup installation files
    cleanup_after_install
    
    echo ""
    echo -e "  ${GREEN}${BOLD}Installation complete!${NC}"
    echo ""
    echo -e "  ${DIM}Backup saved to:${NC}"
    echo -e "  $BACKUP_FILE"
    echo ""
    echo -e "  ${YELLOW}Refresh your browser (Ctrl+Shift+R)${NC}"
    echo ""
}

uninstall() {
    header
    echo -e "  ${BOLD}Uninstalling...${NC}"
    echo ""
    
    check_root
    
    # confirm unless quiet mode
    if ! $QUIET && [[ -t 0 ]]; then
        echo -ne "  ${YELLOW}Are you sure? [y/N]:${NC} "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "  ${DIM}Cancelled${NC}"
            exit 0
        fi
        echo ""
    fi
    
    log "Starting uninstall"
    
    # restore template
    step "Restoring template"
    if [[ -d "$BACKUP_DIR" ]]; then
        LATEST=$(ls -t "$BACKUP_DIR"/index.html.tpl.*.bak 2>/dev/null | head -1)
        if [[ -f "$LATEST" ]]; then
            cp "$LATEST" "$TEMPLATE"
            log "Restored template from $LATEST"
        else
            sed -i '/no-popup\.js/d' "$TEMPLATE" 2>/dev/null
        fi
    fi
    step_ok "Restoring template"
    progress 0.4
    
    # remove files
    step "Removing files"
    rm -f "$JS_LINK"
    rm -rf /usr/local/share/pve-nag-fix
    rm -f "$CRON_FILE"
    rm -f /etc/apt/apt.conf.d/99-pve-nag-fix
    step_ok "Removing files"
    progress 0.5
    
    # restart
    step "Restarting pveproxy"
    if systemctl is-active --quiet pveproxy 2>/dev/null; then
        systemctl restart pveproxy
    fi
    step_ok "Restarting pveproxy"
    progress 0.3
    
    log "Uninstall completed"
    
    echo ""
    echo -e "  ${GREEN}${BOLD}Uninstall complete!${NC}"
    echo ""
    echo -e "  ${YELLOW}Refresh your browser (Ctrl+Shift+R)${NC}"
    echo ""
}

status() {
    header
    echo -e "  ${BOLD}Status${NC}"
    echo ""
    
    # pve version
    if command -v pveversion &>/dev/null; then
        echo -e "  ${DIM}$(pveversion)${NC}"
        echo ""
    fi
    
    # version check
    if [[ -f "$VERSION_FILE" ]]; then
        INSTALLED_VER=$(cat "$VERSION_FILE")
        if [[ "$INSTALLED_VER" != "$VERSION" ]]; then
            echo -e "  ${YELLOW}Update available: v$INSTALLED_VER -> v$VERSION${NC}"
            echo -e "  ${DIM}Run: ./pve-nag-fix.sh uninstall && ./pve-nag-fix.sh install${NC}"
            echo ""
        else
            echo -e "  ${GREEN}Installed version: v$INSTALLED_VER (up to date)${NC}"
            echo ""
        fi
    fi
    
    # components with health score
    local health=0
    local total=5
    
    echo -e "  ${BOLD}Components:${NC}"
    if [[ -f "$JS_SOURCE" ]]; then
        echo -e "    ${CHECK} JS file"
        ((health++)) || true
    else
        echo -e "    ${CROSS} JS file"
    fi
    
    if [[ -L "$JS_LINK" ]]; then
        echo -e "    ${CHECK} Symlink"
        ((health++)) || true
    else
        echo -e "    ${CROSS} Symlink"
    fi
    
    if grep -q "no-popup.js" "$TEMPLATE" 2>/dev/null; then
        echo -e "    ${CHECK} Template patched"
        ((health++)) || true
    else
        echo -e "    ${CROSS} Template not patched"
    fi
    
    if [[ -f "$CRON_FILE" ]]; then
        echo -e "    ${CHECK} Cron job"
        ((health++)) || true
    else
        echo -e "    ${CROSS} Cron job"
    fi
    
    if [[ -f "/etc/apt/apt.conf.d/99-pve-nag-fix" ]]; then
        echo -e "    ${CHECK} APT hook"
        ((health++)) || true
    else
        echo -e "    ${CROSS} APT hook"
    fi
    
    # show health score
    echo ""
    if [[ $health -eq $total ]]; then
        echo -e "  ${GREEN}Health: $health/$total (Healthy)${NC}"
    elif [[ $health -gt 0 ]]; then
        echo -e "  ${YELLOW}Health: $health/$total (Degraded)${NC}"
    else
        echo -e "  ${DIM}Health: Not installed${NC}"
    fi
    
    # backups
    if [[ -d "$BACKUP_DIR" ]]; then
        COUNT=$(ls -1 "$BACKUP_DIR"/*.bak 2>/dev/null | wc -l)
        echo ""
        echo -e "  ${BOLD}Backups:${NC} $COUNT file(s)"
        ls -lh "$BACKUP_DIR"/*.bak 2>/dev/null | tail -3 | while read line; do
            echo -e "    ${DIM}$line${NC}"
        done
    fi
    
    echo ""
}

dry_run() {
    header
    echo -e "  ${BOLD}Dry Run${NC} ${DIM}(no changes will be made)${NC}"
    echo ""
    
    check_root
    check_proxmox
    
    already_installed && echo -e "  Status: ${GREEN}Installed${NC}" || echo -e "  Status: ${YELLOW}Not installed${NC}"
    
    echo ""
    echo -e "  ${BOLD}Would create:${NC}"
    echo -e "    - $JS_SOURCE"
    echo -e "    - $JS_LINK ${DIM}(symlink)${NC}"
    echo -e "    - $CRON_FILE"
    echo -e "    - /etc/apt/apt.conf.d/99-pve-nag-fix"
    echo ""
    echo -e "  ${BOLD}Would modify:${NC}"
    echo -e "    - $TEMPLATE"
    echo ""
    echo -e "  ${BOLD}Would backup:${NC}"
    echo -e "    - $TEMPLATE -> $BACKUP_DIR/"
    echo ""
}

cleanup_backups() {
    header
    echo -e "  ${BOLD}Cleanup Backups${NC}"
    echo ""
    
    check_root
    local keep=${1:-3}
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo -e "  ${YELLOW}No backups to clean${NC}"
        echo ""
        exit 0
    fi
    
    local count=$(ls -1 "$BACKUP_DIR"/*.bak 2>/dev/null | wc -l)
    if [[ $count -le $keep ]]; then
        echo -e "  Only $count backup(s), keeping $keep"
        echo -e "  ${YELLOW}Nothing to clean${NC}"
        echo ""
        exit 0
    fi
    
    local to_delete=$((count - keep))
    echo -e "  Removing $to_delete old backup(s), keeping $keep newest"
    echo ""
    
    ls -t "$BACKUP_DIR"/*.bak 2>/dev/null | tail -n $to_delete | while read f; do
        step "Deleting $(basename "$f")"
        rm -f "$f"
        log "Deleted old backup: $f"
        step_ok "Deleting $(basename "$f")"
    done
    
    echo ""
    echo -e "  ${GREEN}${BOLD}Cleanup complete!${NC}"
    echo ""
}

show_log() {
    header
    echo -e "  ${BOLD}Recent Log Entries${NC}"
    echo ""
    
    if [[ -f "$LOG_FILE" ]]; then
        tail -20 "$LOG_FILE" | while read line; do
            echo -e "  ${DIM}$line${NC}"
        done
    else
        echo -e "  ${YELLOW}No log file found${NC}"
    fi
    echo ""
}

multi_install() {
    header
    echo -e "  ${BOLD}Multi-Node Install${NC}"
    echo ""
    
    check_root
    shift
    
    if [[ $# -eq 0 ]]; then
        echo -e "  Usage: $0 multi <node1> <node2> ..."
        echo -e "  Example: $0 multi 10.0.0.1 10.0.0.2"
        echo ""
        exit 1
    fi
    
    local script_path=$(realpath "$0")
    
    for node in "$@"; do
        echo -e "  ${ARROW} ${BOLD}$node${NC}"
        
        # copy script
        step "  Copying script"
        if ! scp -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$script_path" "root@$node:/tmp/pve-nag-fix.sh" 2>/dev/null; then
            step_fail "  Copying script"
            continue
        fi
        step_ok "  Copying script"
        
        # run install
        step "  Running install"
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$node" "chmod +x /tmp/pve-nag-fix.sh && /tmp/pve-nag-fix.sh install --quiet" 2>/dev/null; then
            step_ok "  Running install"
            log "Multi-install: $node succeeded"
        else
            step_fail "  Running install"
            log "Multi-install: $node failed"
        fi
        
        echo ""
    done
    
    echo -e "  ${GREEN}${BOLD}Multi-node install complete!${NC}"
    echo ""
}

list_backups() {
    header
    echo -e "  ${BOLD}Available Backups${NC}"
    echo ""
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z $(ls -A "$BACKUP_DIR"/*.bak 2>/dev/null) ]]; then
        echo -e "  ${YELLOW}No backups found${NC}"
        echo ""
        return
    fi
    
    echo -e "  ${DIM}Timestamp            Size${NC}"
    echo -e "  ${DIM}─────────────────────────────${NC}"
    ls -t "$BACKUP_DIR"/*.bak 2>/dev/null | while read f; do
        local ts=$(basename "$f" | sed 's/index.html.tpl.\([0-9]*\).bak/\1/')
        local size=$(du -h "$f" | cut -f1)
        echo -e "  $ts    $size"
    done
    echo ""
    echo -e "  ${DIM}Use: ./pve-nag-fix.sh rollback <timestamp>${NC}"
    echo ""
}

rollback() {
    header
    echo -e "  ${BOLD}Rollback${NC}"
    echo ""
    
    check_root
    local timestamp="$1"
    
    if [[ -z "$timestamp" ]]; then
        echo -e "  ${YELLOW}Usage: $0 rollback <timestamp>${NC}"
        echo ""
        echo -e "  Available backups:"
        ls -t "$BACKUP_DIR"/*.bak 2>/dev/null | while read f; do
            local ts=$(basename "$f" | sed 's/index.html.tpl.\([0-9]*\).bak/\1/')
            echo -e "    - $ts"
        done
        echo ""
        exit 1
    fi
    
    local backup_file="$BACKUP_DIR/index.html.tpl.${timestamp}.bak"
    
    if [[ ! -f "$backup_file" ]]; then
        step_fail "Finding backup"
        echo -e "  ${RED}Backup not found: $timestamp${NC}"
        echo ""
        echo -e "  Available backups:"
        ls -t "$BACKUP_DIR"/*.bak 2>/dev/null | while read f; do
            local ts=$(basename "$f" | sed 's/index.html.tpl.\([0-9]*\).bak/\1/')
            echo -e "    - $ts"
        done
        echo ""
        exit 1
    fi
    
    step "Restoring from $timestamp"
    cp "$backup_file" "$TEMPLATE"
    log "Rolled back to backup: $backup_file"
    step_ok "Restoring from $timestamp"
    
    step "Restarting pveproxy"
    if systemctl is-active --quiet pveproxy 2>/dev/null; then
        systemctl restart pveproxy
    fi
    step_ok "Restarting pveproxy"
    
    echo ""
    echo -e "  ${GREEN}${BOLD}Rollback complete!${NC}"
    echo -e "  ${DIM}Restored from: $backup_file${NC}"
    echo ""
    echo -e "  ${YELLOW}Refresh your browser (Ctrl+Shift+R)${NC}"
    echo ""
}

repair() {
    header
    echo -e "  ${BOLD}Repair Installation${NC}"
    echo ""
    
    check_root
    check_proxmox
    log "Starting repair"
    
    local fixed=0
    
    # ensure directories exist
    mkdir -p /usr/local/share/pve-nag-fix 2>/dev/null
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    
    # fix JS file if missing
    if [[ ! -f "$JS_SOURCE" ]]; then
        step "Recreating JS file"
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
        step_ok "Recreating JS file"
        ((fixed++)) || true
    fi
    
    # fix symlink if missing/broken
    if [[ ! -L "$JS_LINK" ]] || [[ ! -e "$JS_LINK" ]]; then
        step "Fixing symlink"
        ln -sf "$JS_SOURCE" "$JS_LINK"
        step_ok "Fixing symlink"
        ((fixed++)) || true
    fi
    
    # fix template if not patched
    if ! grep -q "no-popup.js" "$TEMPLATE" 2>/dev/null; then
        step "Patching template"
        if grep -q "</head>" "$TEMPLATE"; then
            sed -i "s|</head>|$SCRIPT_TAG\n</head>|" "$TEMPLATE"
            step_ok "Patching template"
            ((fixed++)) || true
        else
            step_fail "Patching template"
        fi
    fi
    
    # fix cron if missing
    if [[ ! -f "$CRON_FILE" ]]; then
        step "Recreating cron job"
        cat > "$CRON_FILE" << EOF
@reboot root sleep 30 && ln -sf $JS_SOURCE $JS_LINK 2>/dev/null
EOF
        chmod 644 "$CRON_FILE"
        step_ok "Recreating cron job"
        ((fixed++)) || true
    fi
    
    # fix APT hook if missing
    if [[ ! -f "/etc/apt/apt.conf.d/99-pve-nag-fix" ]]; then
        step "Recreating APT hook"
        cat > /etc/apt/apt.conf.d/99-pve-nag-fix << EOF
DPkg::Post-Invoke { "[ -f $JS_SOURCE ] && ln -sf $JS_SOURCE $JS_LINK 2>/dev/null || true"; };
EOF
        step_ok "Recreating APT hook"
        ((fixed++)) || true
    fi
    
    # restart pveproxy if we fixed something
    if [[ $fixed -gt 0 ]]; then
        step "Restarting pveproxy"
        if systemctl is-active --quiet pveproxy 2>/dev/null; then
            systemctl restart pveproxy
        fi
        step_ok "Restarting pveproxy"
        progress 0.5
    fi
    
    log "Repair completed - fixed $fixed component(s)"
    
    echo ""
    if [[ $fixed -gt 0 ]]; then
        echo -e "  ${GREEN}${BOLD}Repair complete!${NC} Fixed $fixed component(s)"
        echo ""
        echo -e "  ${YELLOW}Refresh your browser (Ctrl+Shift+R)${NC}"
    else
        echo -e "  ${GREEN}All components OK, nothing to repair${NC}"
    fi
    echo ""
}

show_help() {
    header
    echo -e "  ${BOLD}Usage:${NC} $0 <command> [options]"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    install          Install popup removal"
    echo -e "    uninstall        Remove and restore original"
    echo -e "    status           Show current state and health"
    echo -e "    repair           Fix degraded installation"
    echo -e "    dry-run          Preview changes"
    echo -e "    cleanup [N]      Remove old backups, keep N ${DIM}(default: 3)${NC}"
    echo -e "    rollback <ts>    Restore specific backup by timestamp"
    echo -e "    backups          List available backups"
    echo -e "    log              Show recent log entries"
    echo -e "    multi <nodes>    Install on multiple nodes via SSH"
    echo -e "    version          Show version"
    echo ""
    echo -e "  ${BOLD}Options:${NC}"
    echo -e "    -q, --quiet      Suppress graphical output"
    echo -e "    -h, --help       Show this help message"
    echo ""
    echo -e "  ${BOLD}Examples:${NC}"
    echo -e "    $0 install"
    echo -e "    $0 install --quiet"
    echo -e "    $0 repair"
    echo -e "    $0 cleanup 5"
    echo -e "    $0 rollback 20251202143022"
    echo -e "    $0 multi 10.0.0.1 10.0.0.2"
    echo ""
}

# handle quiet mode globally
QUIET=false
for arg in "$@"; do
    if [[ "$arg" == "--quiet" ]] || [[ "$arg" == "-q" ]]; then
        QUIET=true
        break
    fi
done

if $QUIET; then
    header() { :; }
    step() { :; }
    step_ok() { :; }
    step_fail() { echo "FAILED: $1"; }
    progress() { :; }
fi

case "${1:-}" in
    install) install ;;
    uninstall|remove) uninstall ;;
    status) status ;;
    repair|fix) repair ;;
    dry-run) dry_run ;;
    cleanup) cleanup_backups "${2:-3}" ;;
    rollback) rollback "${2:-}" ;;
    backups) list_backups ;;
    log) show_log ;;
    multi) multi_install "$@" ;;
    version|-v|--version) echo "v$VERSION" ;;
    -h|--help|help) show_help ;;
    *) show_help ;;
esac
