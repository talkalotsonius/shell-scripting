#!/usr/bin/env bash
set -euo pipefail

# Configure this Linux Mint VM's hostname and MintWinShare Samba share.
#
# Usage:
#   sudo bash ~/scripts/setup-localvm-agent.sh 2
#   sudo bash ~/scripts/setup-localvm-agent.sh     (prompts for the number)
# Agent numbers must contain 1-4 digits; leading zeros are preserved.
#
# Requires Bash 4+, systemd, installed Samba, standard Linux utilities,
# and a regular local user. Does not install packages or require Python.
# Sources ~/shell-lib/common-shell-functions.sh for scoped logging.
# Set NO_COLOR to disable terminal colours; redirected logs are always plain.
# Uses LM-AI-AGENT<number> for both the hostname and Samba name.
# Clients can use \\LM-AI-AGENT<number>\MintWinShare or the machine's IP.
#
# SECURITY: Preserves guest read/write sharing as the invoking user.
# Use only on a trusted network; Windows may block guest SMB connections.
# If UFW is active, allows its Samba profile without enabling UFW itself.
# Enables and restarts smbd/nmbd, which can interrupt existing connections.
#
# Original configuration is saved under /etc/samba/localvm-agent-backup.*.
# Backups contain smb.conf, hosts, the static hostname, and usershares.
# Failures stop the script but do not automatically undo completed changes.
# For manual recovery, restore those files and the saved hostname, then
# restart Samba; firewall rules and service enablement are not backed up.

readonly TARGET_USER=${SUDO_USER:-$(id -un)}
if [[ "$TARGET_USER" == root ]]; then
    printf 'Run this script with sudo from a regular user account.\n' >&2
    exit 1
fi
user_record=$(getent passwd "$TARGET_USER")
IFS=: read -r _ _ _ _ _ user_home _ <<< "$user_record"
if [[ -z "$user_home" || ! -d "$user_home" ]]; then
    printf 'Cannot find the home directory for %s.\n' "$TARGET_USER" >&2
    exit 1
fi
readonly USER_HOME="$user_home"
readonly LOG_LIBRARY="$USER_HOME/shell-lib/common-shell-functions.sh"
readonly SCOPE=localvm-agent
if [[ ! -r "$LOG_LIBRARY" ]]; then
    printf '[%s] Cannot read logging library: %s\n' "$SCOPE" "$LOG_LIBRARY" >&2
    exit 1
fi
# shellcheck source=../../../lib/common-shell-functions.sh
source "$LOG_LIBRARY"

_info()    { info    "$1" "${SCOPE}"; }
_success() { success "$1" "${SCOPE}"; }
_warn()    { warn    "$1" "${SCOPE}"; }
_error()   { error   "$1" "${SCOPE}"; }

usage() {
    echo "Usage: sudo $0 [agent-number]"
    echo ""
    echo "Arguments:"
    echo "  agent-number    1-4 digits; prompted for when omitted"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help and exit"
    echo ""
    echo "Sets the hostname and Samba name to LM-AI-AGENT<number>."
    echo "Shares $USER_HOME/MintWinShare with guest read/write access."
}

# Called indirectly by the ERR trap.
# shellcheck disable=SC2317
report_setup_error() {
    local status="$1"
    local failed_line="$2"
    _error "Setup failed at line $failed_line (exit $status); completed changes are not automatically rolled back."
    if [[ -n "${backup_directory:-}" ]]; then
        _warn "Configuration backup: $backup_directory"
    fi
    exit "$status"
}
trap 'report_setup_error "$?" "$LINENO"' ERR

# Validate input and privileges before making any system changes.
if (( $# > 1 )); then
    _error 'Expected at most one agent number.'
    usage >&2
    exit 1
fi
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
    usage
    exit 0
fi

agent_number=${1:-}
if [[ -z "$agent_number" ]]; then
    read -r -p 'Agent number (max. 4 digits): ' agent_number
fi
if [[ ! "$agent_number" =~ ^[0-9]{1,4}$ ]]; then
    _error 'Agent number must contain 1-4 digits.'
    usage >&2
    exit 1
fi
if (( EUID != 0 )); then
    _error "Run this script with sudo: sudo bash $0 $agent_number"
    exit 1
fi

# The shared hostname and Samba name must fit NetBIOS's 15-character limit.
readonly MACHINE_NAME="LM-AI-AGENT${agent_number}"
readonly SHARE_PATH="$USER_HOME/MintWinShare"
readonly SAMBA_CONFIG=/etc/samba/smb.conf
readonly SECTION_PATTERN='^[[:space:]]*\[([^]]+)\][[:space:]]*$'

# Check this machine's required tools, account, services, and share path.
_info "Checking prerequisites for $MACHINE_NAME."
for required_command in hostnamectl testparm systemctl runuser net; do
    require_tool "$required_command" "$SCOPE"
done
id "$TARGET_USER" >/dev/null
[[ -f "$SAMBA_CONFIG" && -f /etc/hosts ]]
systemctl cat smbd.service nmbd.service >/dev/null
if [[ -L "$SHARE_PATH" || ( -e "$SHARE_PATH" && ! -d "$SHARE_PATH" ) ]]; then
    _error 'Share path must be a directory, not a symlink or other file.'
    exit 1
fi
_success 'Prerequisite checks passed.'
_warn "Guest read/write access will be enabled as $TARGET_USER; use only on a trusted network."

# Build and validate a candidate before replacing the live configuration.
# testparm normalizes existing settings; original comments are kept in backup.
# Copy unrelated settings unchanged, replacing only the name and share section.
_info 'Preparing and validating Samba configuration.'
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
testparm -s "$SAMBA_CONFIG" > "$temporary_directory/smb.conf.original"
{
    section=
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $SECTION_PATTERN ]]; then
            section=${BASH_REMATCH[1],,}
            if [[ "$section" == mintwinshare ]]; then
                continue
            fi
            printf '%s\n' "$line"
            if [[ "$section" == global ]]; then
                printf '\tnetbios name = %s\n' "$MACHINE_NAME"
            fi
        elif [[ "$section" != mintwinshare ]]; then
            if [[ "$section" == global && "${line,,}" =~ ^[[:space:]]*netbios[[:space:]]+name[[:space:]]*= ]]; then
                continue
            fi
            printf '%s\n' "$line"
        fi
    done < "$temporary_directory/smb.conf.original"
    # Using the invoking user avoids traversal failures through their private home.
    printf '\n[MintWinShare]\n\tpath = %s\n' "$SHARE_PATH"
    printf '\t%s\n' \
        'browseable = yes' \
        'read only = no' \
        'guest ok = yes' \
        "force user = $TARGET_USER" \
        'create mask = 0664' \
        'directory mask = 0775'
} > "$temporary_directory/smb.conf"
testparm -s "$temporary_directory/smb.conf" >/dev/null
_success 'Candidate Samba configuration is valid.'

# Update the local hostname mapping while keeping other entries and aliases.
_info 'Preparing the local hostname mapping.'
old_hostname=$(hostnamectl --static)
awk -v machine_name="$MACHINE_NAME" -v old_hostname="$old_hostname" '
    $1 == "127.0.1.1" {
        printf "127.0.1.1\t%s", machine_name
        for (field = 2; field <= NF; field++) {
            if ($field == "#") {
                for (; field <= NF; field++) printf " %s", $field
                break
            }
            if (tolower($field) != tolower(old_hostname) && tolower($field) != tolower(machine_name))
                printf " %s", $field
        }
        printf "\n"
        found = 1
        next
    }
    { print }
    END { if (!found) printf "127.0.1.1\t%s\n", machine_name }
' /etc/hosts > "$temporary_directory/hosts"

# Keep a separate backup for every run, including the original usershares.
_info 'Backing up the current configuration.'
backup_directory=$(mktemp -d /etc/samba/localvm-agent-backup.XXXXXX)
cp -a "$SAMBA_CONFIG" "$backup_directory/smb.conf"
cp -a /etc/hosts "$backup_directory/hosts"
printf '%s\n' "$old_hostname" > "$backup_directory/hostname"
if [[ -d /var/lib/samba/usershares ]]; then
    cp -a /var/lib/samba/usershares "$backup_directory/usershares"
fi
_success "Configuration backup: $backup_directory"

# Create a missing folder; never recursively change existing file permissions.
if [[ ! -d "$SHARE_PATH" ]]; then
    _info "Creating share directory: $SHARE_PATH"
    install -d -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" -m 0775 "$SHARE_PATH"
fi
if ! runuser -u "$TARGET_USER" -- test -r "$SHARE_PATH" ||
   ! runuser -u "$TARGET_USER" -- test -w "$SHARE_PATH" ||
   ! runuser -u "$TARGET_USER" -- test -x "$SHARE_PATH"; then
    _error "$TARGET_USER needs read, write, and traversal permissions on $SHARE_PATH."
    _error "Configuration backup: $backup_directory"
    exit 1
fi
_success "Share directory permissions verified: $SHARE_PATH"

# Migrate the desktop-created usershare to smb.conf to avoid duplicate shares.
usershare_info=$(runuser -u "$TARGET_USER" -- net usershare info MintWinShare)
if [[ -n "$usershare_info" ]]; then
    _info 'Migrating the existing MintWinShare usershare to smb.conf.'
    runuser -u "$TARGET_USER" -- net usershare delete MintWinShare
fi
_info 'Installing Samba configuration and the local hostname mapping.'
install -o root -g root -m 0644 "$temporary_directory/smb.conf" "$SAMBA_CONFIG"
# Write in place to preserve /etc/hosts file metadata.
cat "$temporary_directory/hosts" > /etc/hosts
_info "Setting the machine name to $MACHINE_NAME."
hostnamectl set-hostname "$MACHINE_NAME" --static
hostnamectl set-hostname "$MACHINE_NAME" --pretty
testparm -s "$SAMBA_CONFIG" >/dev/null
_success 'Hostname and Samba configuration applied.'
# Open SMB ports only if UFW is already active, then apply the service changes.
if command -v ufw >/dev/null 2>&1; then
    firewall_status=$(LC_ALL=C ufw status)
    if [[ "$firewall_status" == *'Status: active'* ]]; then
        _info 'Allowing the Samba profile through the active UFW firewall.'
        ufw allow Samba
    else
        _info 'UFW is inactive; no firewall changes made.'
    fi
else
    _info 'UFW is not installed; no firewall changes made.'
fi
_info 'Enabling and restarting Samba services.'
systemctl enable smbd nmbd
systemctl restart smbd nmbd
systemctl is-active --quiet smbd nmbd

_success 'Samba services are active.'
_info "Machine name: $MACHINE_NAME"
_info "Windows share: \\\\${MACHINE_NAME}\\MintWinShare"
_warn 'Windows clients that block guest access will require authenticated sharing instead.'
_success 'Machine and share setup completed.'
