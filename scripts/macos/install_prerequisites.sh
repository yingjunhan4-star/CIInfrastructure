#!/usr/bin/env bash
set -euo pipefail
ALL=false; DRY=false; packages=()
while [[ $# -gt 0 ]]; do case "$1" in --all) ALL=true; shift;; --java) packages+=(openjdk@17); shift;; --powershell) packages+=(powershell); shift;; --python) packages+=(python); shift;; --subversion) packages+=(subversion); shift;; --dry-run) DRY=true; shift;; *) echo "Usage: $0 [--all] [--java] [--powershell] [--python] [--subversion] [--dry-run]"; exit 1;; esac; done
command -v brew >/dev/null 2>&1 || { echo 'Homebrew is required.' >&2; exit 1; }
if $ALL; then packages=(openjdk@17 jq powershell python subversion); fi
for package in "${packages[@]}"; do if $DRY; then echo "[DryRun] brew install $package"; else brew install "$package"; fi; done
echo 'Restart the Jenkins process after installation so it receives the updated PATH.'
