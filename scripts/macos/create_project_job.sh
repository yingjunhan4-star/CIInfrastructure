#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_HOME="${JENKINS_HOME:-$(dirname "$SCRIPT_DIR")/.jenkins}"
TEMPLATE_PATH=""; JOB_NAME=""; DRY_RUN=false
die() { echo "ERROR: $*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do case "$1" in
  --template) TEMPLATE_PATH="$2"; shift 2;; --jenkins-home) JENKINS_HOME="$2"; shift 2;; --job-name) JOB_NAME="$2"; shift 2;; --dry-run) DRY_RUN=true; shift;; *) die "Unknown option: $1";; esac; done
command -v jq >/dev/null || die "jq is required."
[[ -f "$TEMPLATE_PATH" ]] || die "--template must point to a project template."
name="${JOB_NAME:-$(jq -r '.jobName // empty' "$TEMPLATE_PATH")}"; [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Invalid Job name."
job_path="$JENKINS_HOME/jobs/$name"; [[ ! -e "$job_path" ]] || die "Job '$name' already exists; it will not be updated."
escape() { jq -nr --arg value "$1" '$value|@html'; }
remote="$(escape "$(jq -r '.scm.repositoryUrl // empty' "$TEMPLATE_PATH")")"; credentials="$(escape "$(jq -r '.scm.credentialsId // empty' "$TEMPLATE_PATH")")"; script_path="$(escape "$(jq -r '.scm.scriptPath // empty' "$TEMPLATE_PATH")")"
[[ -n "$remote" && -n "$credentials" && -n "$script_path" ]] || die "Template SCM fields are required."
system_user_id="$(jq -r '.environment.GAMEADMIN_JENKINS_SYSTEM_USER_ID // empty' "$TEMPLATE_PATH")"; [[ "$system_user_id" =~ ^[A-Za-z0-9_.-]{1,120}$ ]] || die "environment.GAMEADMIN_JENKINS_SYSTEM_USER_ID must be a valid Jenkins user ID."
parameters="$(jq -r '.parameters[] | .name as $n | .description as $d | if .type=="boolean" then "<hudson.model.BooleanParameterDefinition><name>\($n|@html)</name><description>\($d|@html)</description><defaultValue>\(.defaultValue)</defaultValue></hudson.model.BooleanParameterDefinition>" elif .type=="string" then "<hudson.model.StringParameterDefinition><name>\($n|@html)</name><description>\($d|@html)</description><defaultValue>\(.defaultValue|tostring|@html)</defaultValue><trim>true</trim></hudson.model.StringParameterDefinition>" elif .type=="choice" then "<hudson.model.ChoiceParameterDefinition><name>\($n|@html)</name><description>\($d|@html)</description><choices class=\"java.util.Arrays$ArrayList\"><a class=\"string-array\">" + ([.choices[]|"<string>\(.|@html)</string>"]|join("")) + "</a></choices></hudson.model.ChoiceParameterDefinition>" else error("Unsupported parameter type") end' "$TEMPLATE_PATH")"
[[ "$DRY_RUN" == true ]] && { echo "[DryRun] Would create $job_path from $TEMPLATE_PATH"; exit 0; }
mkdir -p "$job_path"
# [AI] Create once; Jenkins UI owns all parameters after the first creation.
cat > "$job_path/config.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<flow-definition plugin="workflow-job"><actions/><description>Created once by CIInfrastructure from a project template. Jenkins UI owns parameters after creation. GameAdmin automated-build user default: $(escape "$system_user_id").</description><keepDependencies>false</keepDependencies><properties><hudson.model.ParametersDefinitionProperty><parameterDefinitions>$parameters</parameterDefinitions></hudson.model.ParametersDefinitionProperty></properties><definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps"><scm class="hudson.scm.SubversionSCM" plugin="subversion"><locations><hudson.scm.SubversionSCM_-ModuleLocation><remote>$remote</remote><credentialsId>$credentials</credentialsId><local>.</local><depthOption>infinity</depthOption><ignoreExternalsOption>false</ignoreExternalsOption></hudson.scm.SubversionSCM_-ModuleLocation></locations><workspaceUpdater class="hudson.scm.subversion.UpdateUpdater"/></scm><scriptPath>$script_path</scriptPath><lightweight>true</lightweight></definition><triggers/><disabled>false</disabled></flow-definition>
EOF
echo "Created Job '$name'. Restart Jenkins to load it."
