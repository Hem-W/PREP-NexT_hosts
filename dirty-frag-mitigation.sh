#!/usr/bin/env bash
#
# dirty-frag-mitigation.sh
#
# Deploy or remove the mitigation for the "Dirty Frag" Linux kernel local
# privilege escalation vulnerabilities (CVE-2026-43284 and a second CVE whose
# ID is pending at the time of writing), as described by Canonical:
#   https://ubuntu.com/blog/dirty-frag-linux-vulnerability-fixes-available
#
# The mitigation blocks the esp4, esp6 and rxrpc kernel modules from loading.
#
# IMPORTANT: while the mitigation is in place,
#   * IPsec ESP will be broken (e.g. StrongSwan VPNs, IPsec tunnels)
#   * AFS / any other RxRPC consumer will be broken
# Once a patched kernel is installed and the host is rebooted into it, the
# mitigation should be removed with `remove`.
#
# Usage:
#   sudo ./dirty-frag-mitigation.sh apply     # deploy mitigation
#   sudo ./dirty-frag-mitigation.sh remove    # remove mitigation
#   sudo ./dirty-frag-mitigation.sh status    # show current state
#
# Exit codes:
#   0   success
#   2   bad usage
#   3   must run as root
#   10  modules still loaded after unload attempt; reboot required

set -euo pipefail

CONF_FILE="/etc/modprobe.d/dirty-frag.conf"
MODULES=(esp4 esp6 rxrpc)

usage() {
    cat <<EOF
Usage: $0 {apply|remove|status}

  apply   Deploy the Dirty Frag mitigation (blocks ${MODULES[*]} modules).
  remove  Remove the mitigation (use only after installing a patched kernel).
  status  Report whether the mitigation is in place and modules are loaded.

Aliases: apply=deploy=enable, remove=disable, status=check
EOF
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: this script must be run as root (use sudo)." >&2
        exit 3
    fi
}

# Echo (newline-separated) the subset of $MODULES currently loaded.
loaded_modules() {
    for m in "${MODULES[@]}"; do
        if grep -qE "^${m} " /proc/modules; then
            echo "$m"
        fi
    done
}

cmd_status() {
    echo "=== Dirty Frag mitigation status ==="
    if [[ -f "$CONF_FILE" ]]; then
        echo "modprobe block file : PRESENT ($CONF_FILE)"
    else
        echo "modprobe block file : absent"
    fi

    local loaded
    loaded="$(loaded_modules | tr '\n' ' ' | sed 's/ $//')"
    if [[ -n "$loaded" ]]; then
        echo "kernel modules      : LOADED ($loaded)"
    else
        echo "kernel modules      : not loaded"
    fi
}

cmd_apply() {
    require_root

    echo "[1/3] Writing module block file: $CONF_FILE"
    {
        echo "# Dirty Frag mitigation"
        echo "# https://ubuntu.com/blog/dirty-frag-linux-vulnerability-fixes-available"
        for m in "${MODULES[@]}"; do
            echo "install $m /bin/false"
        done
    } > "$CONF_FILE"

    echo "[2/3] Regenerating initramfs images (this may take a minute)..."
    update-initramfs -u -k all

    echo "[3/3] Unloading modules if currently loaded"
    for m in "${MODULES[@]}"; do
        if grep -qE "^${m} " /proc/modules; then
            if rmmod "$m" 2>/dev/null; then
                echo "  - $m: unloaded"
            else
                echo "  - $m: in use, could not unload"
            fi
        else
            echo "  - $m: not loaded"
        fi
    done

    local still
    still="$(loaded_modules | tr '\n' ' ' | sed 's/ $//')"
    if [[ -n "$still" ]]; then
        echo
        echo "WARNING: the following modules are still loaded because they are in use:"
        echo "  $still"
        echo
        echo "A reboot is required to fully enforce the mitigation:"
        echo "  sudo reboot"
        exit 10
    fi

    echo
    echo "Mitigation applied successfully. Affected modules are blocked and not loaded."
}

cmd_remove() {
    require_root

    if [[ -f "$CONF_FILE" ]]; then
        echo "[1/2] Removing $CONF_FILE"
        rm -f "$CONF_FILE"
    else
        echo "[1/2] $CONF_FILE not present, nothing to remove"
    fi

    echo "[2/2] Regenerating initramfs images..."
    update-initramfs -u -k all

    echo
    echo "Mitigation removed. Ensure a patched kernel is installed and that you"
    echo "have rebooted into it before relying on esp4/esp6/rxrpc functionality."
}

main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 2
    fi
    case "$1" in
        apply|deploy|enable)  cmd_apply  ;;
        remove|disable)       cmd_remove ;;
        status|check)         cmd_status ;;
        -h|--help|help)       usage      ;;
        *)                    usage; exit 2 ;;
    esac
}

main "$@"
