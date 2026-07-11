#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_HOME="${JENKINS_HOME:-$(dirname "$SCRIPT_DIR")/.jenkins}"
JENKINS_WAR="${JENKINS_WAR:-}"
PID_FILE="$JENKINS_HOME/jenkins.pid"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ ! -f "$PID_FILE" ]]; then
  echo "No Jenkins PID file found: $PID_FILE"
  exit 0
fi

if [[ -z "$JENKINS_WAR" ]]; then
  JENKINS_WAR="$(find "$JENKINS_HOME" -maxdepth 1 -name 'jenkins-*.war' -type f -print -quit 2>/dev/null || true)"
fi

jenkins_pid="$(tr -d '[:space:]' < "$PID_FILE")"
if ! [[ "$jenkins_pid" =~ ^[0-9]+$ ]]; then
  die "Invalid Jenkins PID: $jenkins_pid"
fi

if ps -p "$jenkins_pid" >/dev/null 2>&1; then
  command_line="$(ps -p "$jenkins_pid" -o command= 2>/dev/null || true)"
  if [[ -n "$JENKINS_WAR" && "$command_line" != *"$JENKINS_HOME"* && "$command_line" != *"$JENKINS_WAR"* ]]; then
    die "PID $jenkins_pid does not belong to JenkinsHome $JENKINS_HOME."
  fi

  kill "$jenkins_pid"
  for _ in $(seq 1 10); do
    if ! kill -0 "$jenkins_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if kill -0 "$jenkins_pid" >/dev/null 2>&1; then
    kill -9 "$jenkins_pid"
  fi
  echo "Stopped Jenkins. PID=$jenkins_pid"
else
  echo "Jenkins process is not running. PID=$jenkins_pid"
fi

rm -f "$PID_FILE"
