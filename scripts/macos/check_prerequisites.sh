#!/usr/bin/env bash
set -euo pipefail

required_commands=(java curl lsof jq)
missing=()

echo "macOS CIInfrastructure prerequisites:"
for command_name in "${required_commands[@]}"; do
  if command -v "$command_name" >/dev/null 2>&1; then
    echo "[OK] $command_name: $(command -v "$command_name")"
  else
    echo "[MISSING] $command_name"
    missing+=("$command_name")
  fi
done

if command -v java >/dev/null 2>&1; then
  java_major="$(java -version 2>&1 | head -n 1 | sed -E 's/.*version "([^"]+)".*/\1/' | awk -F. '{ if ($1 == 1) print $2; else print $1 }')"
  if [[ "$java_major" =~ ^[0-9]+$ && "$java_major" -ge 17 ]]; then
    echo "[OK] Java major version: $java_major"
  else
    echo "[MISSING] Java 17 (found major version: ${java_major:-unknown})"
    missing+=(java-17)
  fi
fi

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo
  echo "Run install_prerequisites.sh to choose missing Homebrew packages."
  exit 1
fi
