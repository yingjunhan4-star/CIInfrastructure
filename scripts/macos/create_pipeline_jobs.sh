#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_HOME="${JENKINS_HOME:-$(dirname "$SCRIPT_DIR")/.jenkins}"
CONFIG_PATH="${CONFIG_PATH:-}"
DRY_RUN=false

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: create_pipeline_jobs.sh --config PATH [--jenkins-home PATH] [--dry-run]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --jenkins-home) JENKINS_HOME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required to parse jobs.json."
[[ -n "$CONFIG_PATH" ]] || die "--config is required."
[[ -f "$CONFIG_PATH" ]] || die "Job configuration not found: $CONFIG_PATH"
jq -e '.jobs | type == "array"' "$CONFIG_PATH" >/dev/null || die "jobs must be an array."

xml_escape() {
  printf '%s' "$1" | jq -Rr @html
}

job_count="$(jq '.jobs | length' "$CONFIG_PATH")"
for ((index = 0; index < job_count; index++)); do
  name="$(jq -r ".jobs[$index].name // empty" "$CONFIG_PATH")"
  repository_url="$(jq -r ".jobs[$index].repositoryUrl // empty" "$CONFIG_PATH")"
  credentials_id="$(jq -r ".jobs[$index].credentialsId // empty" "$CONFIG_PATH")"
  script_path="$(jq -r ".jobs[$index].scriptPath // empty" "$CONFIG_PATH")"

  [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Invalid Job name: $name"
  [[ -n "$repository_url" && -n "$credentials_id" && -n "$script_path" ]] ||
    die "Job $name is missing repositoryUrl, credentialsId or scriptPath."
  [[ "$script_path" != /* && "$script_path" != *".."* ]] ||
    die "Job $name scriptPath must stay inside the SCM workspace."

  escaped_url="$(xml_escape "$repository_url")"
  escaped_credentials="$(xml_escape "$credentials_id")"
  escaped_script="$(xml_escape "$script_path")"
  output_path="$JENKINS_HOME/jobs/$name/config.xml"

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DryRun] Would write $output_path"
    echo "[DryRun] $name <= $repository_url / $script_path"
    continue
  fi

  mkdir -p "$(dirname "$output_path")"
  cat > "$output_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Managed by CIInfrastructure. Do not edit generated config.xml manually.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.scm.SubversionSCM" plugin="subversion">
      <locations>
        <hudson.scm.SubversionSCM_-ModuleLocation>
          <remote>$escaped_url</remote>
          <credentialsId>$escaped_credentials</credentialsId>
          <local>.</local>
          <depthOption>infinity</depthOption>
          <ignoreExternalsOption>true</ignoreExternalsOption>
        </hudson.scm.SubversionSCM_-ModuleLocation>
      </locations>
      <excludedRegions/>
      <excludedUsers/>
      <excludedCommitMessages/>
      <workspaceUpdater class="hudson.scm.subversion.UpdateWithCleanUpdater"/>
    </scm>
    <scriptPath>$escaped_script</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <disabled>false</disabled>
</flow-definition>
EOF
  echo "Created or updated Pipeline Job: $name"
done

if [[ "$job_count" -eq 0 ]]; then
  echo "No jobs configured in $CONFIG_PATH."
fi
