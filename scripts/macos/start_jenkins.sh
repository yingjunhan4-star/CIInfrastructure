#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_HOME="${JENKINS_HOME:-$(dirname "$SCRIPT_DIR")/.jenkins}"
JENKINS_WAR="${JENKINS_WAR:-}"
JENKINS_VERSION="${JENKINS_VERSION:-2.541.3}"
PORT="${PORT:-8080}"
LISTEN_ADDRESS="${LISTEN_ADDRESS:-127.0.0.1}"
SKIP_PLUGIN_INSTALL=false

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: start_jenkins.sh [options]

Options:
  --jenkins-home PATH
  --jenkins-war PATH
  --version VERSION
  --port PORT
  --listen-address ADDRESS
  --skip-plugin-install
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jenkins-home) JENKINS_HOME="$2"; shift 2 ;;
    --jenkins-war) JENKINS_WAR="$2"; shift 2 ;;
    --version) JENKINS_VERSION="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --listen-address) LISTEN_ADDRESS="$2"; shift 2 ;;
    --skip-plugin-install) SKIP_PLUGIN_INSTALL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

command -v java >/dev/null 2>&1 || die "java is required."
command -v curl >/dev/null 2>&1 || die "curl is required."
command -v lsof >/dev/null 2>&1 || die "lsof is required."

if [[ -z "$JENKINS_WAR" ]]; then
  JENKINS_WAR="$JENKINS_HOME/jenkins-$JENKINS_VERSION.war"
fi

mkdir -p "$JENKINS_HOME/logs"

download_file() {
  local url="$1"
  local output="$2"
  mkdir -p "$(dirname "$output")"
  curl -fsSL --retry 3 -o "$output" "$url"
}

ensure_plugins() {
  local plugins_dir="$JENKINS_HOME/plugins"
  local tools_dir="$JENKINS_HOME/tools"
  local manager="$tools_dir/jenkins-plugin-manager.jar"
  local plugin_list="$tools_dir/plugins.txt"
  local plugin
  local required_plugins=(workflow-aggregator pipeline-stage-view subversion ssh-agent)

  mkdir -p "$plugins_dir" "$tools_dir"
  for plugin in "${required_plugins[@]}"; do
    if [[ ! -f "$plugins_dir/$plugin.jpi" && ! -f "$plugins_dir/$plugin.hpi" ]]; then
      if [[ ! -f "$manager" ]]; then
        download_file \
          "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar" \
          "$manager"
      fi
      printf '%s\n' "${required_plugins[@]}" > "$plugin_list"
      java -jar "$manager" \
        --war "$JENKINS_WAR" \
        --plugin-download-directory "$plugins_dir" \
        --plugin-file "$plugin_list"
      return
    fi
  done
}

listening_pid() {
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
}

process_command() {
  ps -p "$1" -o command= 2>/dev/null || true
}

is_managed_process() {
  local command_line
  command_line="$(process_command "$1")"
  [[ "$command_line" == *"$JENKINS_HOME"* || "$command_line" == *"$JENKINS_WAR"* ]]
}

wait_for_jenkins() {
  local attempt
  for attempt in $(seq 1 60); do
    if curl -fsS --max-time 5 "http://127.0.0.1:$PORT/api/json" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  [[ -f "$JENKINS_HOME/logs/jenkins.err.log" ]] && tail -n 30 "$JENKINS_HOME/logs/jenkins.err.log"
  return 1
}

if [[ ! -f "$JENKINS_WAR" ]]; then
  download_file "https://get.jenkins.io/war-stable/$JENKINS_VERSION/jenkins.war" "$JENKINS_WAR"
fi

if [[ "$SKIP_PLUGIN_INSTALL" != true ]]; then
  ensure_plugins
fi

existing_pid="$(listening_pid)"
if [[ -n "$existing_pid" ]]; then
  if is_managed_process "$existing_pid"; then
    echo "Jenkins is already running. PID=$existing_pid URL=http://$LISTEN_ADDRESS:$PORT/"
    exit 0
  fi
  die "Port $PORT is already used by process $existing_pid."
fi

stdout_log="$JENKINS_HOME/logs/jenkins.out.log"
stderr_log="$JENKINS_HOME/logs/jenkins.err.log"
export JENKINS_HOME
nohup java \
  -Djenkins.install.runSetupWizard=false \
  -Dfile.encoding=UTF-8 \
  -Dsun.stdout.encoding=UTF-8 \
  -Dsun.stderr.encoding=UTF-8 \
  -jar "$JENKINS_WAR" \
  "--httpPort=$PORT" \
  "--httpListenAddress=$LISTEN_ADDRESS" \
  >"$stdout_log" 2>"$stderr_log" &

jenkins_pid=$!
echo "$jenkins_pid" > "$JENKINS_HOME/jenkins.pid"
if ! wait_for_jenkins; then
  die "Jenkins did not become ready. Check $stderr_log."
fi

echo "Started Jenkins. PID=$jenkins_pid"
echo "JENKINS_HOME=$JENKINS_HOME"
echo "URL=http://$LISTEN_ADDRESS:$PORT/"
