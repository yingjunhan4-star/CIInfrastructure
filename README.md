# CI Infrastructure

本仓库只维护共享 Jenkins 生命周期与一种 Job 创建机制：项目保留自己的模板，CIInfrastructure 只创建不存在的 Pipeline Job。创建完成后，Job 参数和默认值完全由 Jenkins UI 维护；创建器绝不更新、合并或重置已有 Job。

## 目录

```text
scripts/
├── windows/ create_project_job.ps1/.bat、start/stop/healthcheck
└── macos/   create_project_job.sh、start/stop/healthcheck
```

`JENKINS_HOME` 默认是 `scripts/.jenkins`，端口 `8080`，监听地址 `127.0.0.1`。启动、停止和创建 Job 时必须使用同一个 Jenkins Home。

## 项目模板

项目在自身仓库维护模板，例如：

```text
ci/jenkins/jobs/package-job.json
```

模板定义 Job 名称、SVN SCM、Jenkinsfile 路径，以及首次参数的类型和默认值；不得包含 Token、密码或证书。

模板需满足：`jobName`、`scm.repositoryUrl`、`scm.credentialsId`、`scm.scriptPath` 均非空；参数类型仅支持 `string`、`boolean`、`choice`。项目应在调用创建器前自行校验模板与 Jenkinsfile 的 `params.*` 读取契约。

## 创建新 Job

Windows：

```bat
scripts\windows\create_project_job.bat -TemplatePath G:\Project\ci\jenkins\jobs\package-job.json -DryRun
scripts\windows\create_project_job.bat -TemplatePath G:\Project\ci\jenkins\jobs\package-job.json
```

Windows 创建器默认使用 `<CIInfrastructure>\scripts\.jenkins`，无需传 `-JenkinsHome`；仅在自定义 Jenkins Home 时显式传入该参数。

macOS：

```bash
./scripts/macos/create_project_job.sh --template /path/to/project/ci/jenkins/jobs/package-job.json --dry-run
./scripts/macos/create_project_job.sh --template /path/to/project/ci/jenkins/jobs/package-job.json
```

创建后重启 Jenkins 加载 Job。若同名 Job 已存在，工具会失败且不会修改该 Job；请在 Jenkins UI 的 Job Configure 页面维护参数。

创建器不读取项目构建工具、不定义环境或节点 OS 策略，也不执行打包。项目模板与 Jenkins UI 分别拥有“首次参数”和“创建后的参数”两个阶段的配置权。

## Jenkins 生命周期

Windows 使用 `start_jenkins.bat`、`stop_jenkins.bat`、`healthcheck_jenkins.bat`；macOS 使用同名 `.sh` 脚本。Jenkins 节点所需的 Unity、SVN、Python 与 PowerShell 等工具由节点统一运行契约提供；节点本地 Unity 路径由 `UNITY_EXE` 配置。
