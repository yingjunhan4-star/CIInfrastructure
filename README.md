# Jenkins 运维脚本

本目录只维护 Jenkins 实例的启停、健康检查和 Pipeline Job 配置，不依赖任何 Unity 工程。

## 目录

```text
jenkins-infra/
├── config/
│   ├── jobs.json
│   └── jobs.example.json
├── scripts/
│   ├── start_jenkins.ps1
│   ├── stop_jenkins.ps1
│   ├── healthcheck_jenkins.ps1
│   └── create_pipeline_jobs.ps1
└── README.md
```

## 第一次启动

在 PowerShell 中执行：

```powershell
Set-Location <CIInfrastructure目录>
.\scripts\create_pipeline_jobs.ps1 -ConfigPath .\config\jobs.json -DryRun
.\scripts\create_pipeline_jobs.ps1 -ConfigPath .\config\jobs.json
.\scripts\start_jenkins.ps1
.\scripts\healthcheck_jenkins.ps1
```

默认配置：

```text
JENKINS_HOME=%USERPROFILE%\.jenkins-infra
端口=8080
监听地址=127.0.0.1
```

首次启动前，先根据 `config/jobs.json` 创建 Pipeline Job：

```powershell
.\scripts\create_pipeline_jobs.ps1 -ConfigPath .\config\jobs.json -DryRun
.\scripts\create_pipeline_jobs.ps1 -ConfigPath .\config\jobs.json
```

已有 Jenkins 实例更新 Job 配置时，先执行 `stop_jenkins.ps1`，再生成 Job 配置，最后重新执行 `start_jenkins.ps1`。

Job 使用 `Pipeline script from SCM` 模式。每个 Job 的 SVN 地址和 Jenkinsfile 路径由配置文件指定，Jenkins 自动分配工作区，不使用开发人员工作副本，也不设置 `customWorkspace`。

## 停止 Jenkins

```powershell
.scripts\stop_jenkins.ps1
```

## Job 配置

复制 `config/jobs.example.json` 的条目到 `config/jobs.json`，填写实际 SVN 地址和 Jenkins 凭据 ID。凭据只在 Jenkins 页面或 Credentials 中维护，不写入本仓库。

创建远程 SVN 运维目录或提交前，需要先确认 SVN 管理员提供的仓库 URL 和提交权限。本地目录的生成不等于远程 SVN 仓库已经创建。
