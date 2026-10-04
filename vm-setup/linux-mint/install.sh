#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target_user=${SUDO_USER:-$(id -un)}
if [[ "$target_user" == root ]]; then
	printf 'Run this installer as a regular user, or with sudo from that user.\n' >&2
	exit 1
fi
if (( EUID == 0 )); then
	exec runuser -u "$target_user" -- bash "$script_directory/install.sh" "$@"
fi

user_record=$(getent passwd "$target_user")
IFS=: read -r _ _ _ _ _ target_home _ <<< "$user_record"
library_directory="$script_directory/../../lib"
if [[ ! -d "$target_home" || ! -d "$library_directory" ]]; then
	printf 'Cannot find the user home or repository lib directory.\n' >&2
	exit 1
fi

mkdir -p -- "$target_home/shell-lib"
cp -R --preserve=mode -- "$library_directory/." "$target_home/shell-lib/"
cp -R --preserve=mode -- "$script_directory/." "$target_home/"
printf 'Installed Linux Mint scripts in %s and libraries in %s/shell-lib.\n' "$target_home" "$target_home"
