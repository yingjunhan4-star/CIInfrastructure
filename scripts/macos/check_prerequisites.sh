#!/usr/bin/env bash
set -euo pipefail
missing=()
check() { if command -v "$1" >/dev/null 2>&1; then echo "[OK] $1: $(command -v "$1")"; else echo "[MISSING] $1"; missing+=("$1"); fi; }
echo 'macOS CIInfrastructure Controller prerequisites:'
check java; check curl; check lsof; check jq
if command -v java >/dev/null 2>&1; then major="$(java -version 2>&1 | head -n 1 | sed -E 's/.*version "([^"]+)".*/\1/' | awk -F. '{if($1==1) print $2; else print $1}')"; if ! [[ "$major" =~ ^[0-9]+$ && "$major" -ge 17 ]]; then echo "[MISSING] Java 17"; missing+=(java-17); fi; fi
echo 'macOS Jenkins node runtime contract:'
check pwsh; check python3; check svn
if ((${#missing[@]})); then for item in "${missing[@]}"; do case "$item" in pwsh) option=--powershell;; python3) option=--python;; svn) option=--subversion;; java|java-17) option=--java;; *) continue;; esac; echo "  Next: ./install_prerequisites.sh $option --dry-run"; echo "  Install: ./install_prerequisites.sh $option"; done; echo 'Restart Jenkins after installation so its PATH is refreshed.'; exit 1; fi
