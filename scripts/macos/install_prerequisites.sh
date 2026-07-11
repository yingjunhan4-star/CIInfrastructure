#!/usr/bin/env bash
set -euo pipefail

INSTALL_ALL=false
INSTALL_JAVA=false
INSTALL_JQ=false
DRY_RUN=false

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: install_prerequisites.sh [options]

Options:
  --all       Install every missing CIInfrastructure prerequisite.
  --java      Install Java 17 if missing.
  --jq        Install jq if missing.
  --dry-run   Print Homebrew commands without running them.
EOF
}

ask_install() {
  local package_name="$1"
  local answer
  read -r -p "Install $package_name now? [y/N] " answer
  [[ "$answer" =~ ^([yY][eE][sS]|[yY])$ ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) INSTALL_ALL=true; shift ;;
    --java) INSTALL_JAVA=true; shift ;;
    --jq) INSTALL_JQ=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

command -v brew >/dev/null 2>&1 || die "Homebrew is required. Install it from https://brew.sh/ and rerun this script."

java_missing=false
jq_missing=false
java_major=0
if command -v java >/dev/null 2>&1; then
  java_major="$(java -version 2>&1 | head -n 1 | sed -E 's/.*version "([^"]+)".*/\1/' | awk -F. '{ if ($1 == 1) print $2; else print $1 }')"
fi
if ! [[ "$java_major" =~ ^[0-9]+$ && "$java_major" -ge 17 ]]; then
  java_missing=true
fi
command -v jq >/dev/null 2>&1 || jq_missing=true

if [[ "$java_missing" == true && "$INSTALL_ALL" == false && "$INSTALL_JAVA" == false ]]; then
  ask_install "Java 17" && INSTALL_JAVA=true || true
fi
if [[ "$jq_missing" == true && "$INSTALL_ALL" == false && "$INSTALL_JQ" == false ]]; then
  ask_install "jq" && INSTALL_JQ=true || true
fi

if [[ "$INSTALL_ALL" == true ]]; then
  INSTALL_JAVA="$java_missing"
  INSTALL_JQ="$jq_missing"
fi

if [[ "$INSTALL_JAVA" == true && "$java_missing" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DryRun] brew install openjdk@17"
  else
    brew install openjdk@17
  fi
fi

if [[ "$INSTALL_JQ" == true && "$jq_missing" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DryRun] brew install jq"
  else
    brew install jq
  fi
fi

if [[ "$DRY_RUN" == false && "$INSTALL_JAVA" == true && "$java_missing" == true ]]; then
  java_prefix="$(brew --prefix openjdk@17 2>/dev/null || true)"
  if [[ -n "$java_prefix" ]]; then
    echo "Java 17 installed. Add this to your shell profile if java is not found:"
    echo "export PATH=\"$java_prefix/bin:\$PATH\""
  fi
fi
