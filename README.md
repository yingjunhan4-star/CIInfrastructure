# CI Infrastructure

本目录维护跨项目 Jenkins 实例的启停、健康检查和 Pipeline Job 配置，不依赖任何 Unity 工程。

## 目录

```text
jenkins-infra/
├── config/
│   ├── jobs.json              本地配置，不提交
│   └── jobs.example.json      公共示例
├── scripts/
│   ├── start_jenkins.bat
│   ├── start_jenkins.ps1
│   ├── stop_jenkins.bat
│   ├── stop_jenkins.ps1
│   ├── healthcheck_jenkins.bat
│   ├── healthcheck_jenkins.ps1
│   ├── create_pipeline_jobs.bat
│   ├── create_pipeline_jobs.ps1
│   └── macos/
│       ├── start_jenkins.sh
│       ├── stop_jenkins.sh
│       ├── healthcheck_jenkins.sh
│       └── create_pipeline_jobs.sh
└── README.md
```

## 前置条件

Windows：

- Java 17；
- Windows PowerShell；
- Jenkins 节点所需的 SVN、Unity、Node.js 等工具由各项目 Job 自行配置。

macOS：

- Java 17；
- Bash/Zsh；
- `curl`、`lsof`、`jq`；
- Jenkins 节点所需的 SVN、Unity、Node.js 等工具由各项目 Job 自行配置。

macOS 可使用 Homebrew 安装缺少的工具：

```bash
brew install openjdk@17 jq
```

## Windows 使用

Windows 入口使用 `.bat`，由 `.bat` 转调对应的 PowerShell 脚本：

```bat
scripts\create_pipeline_jobs.bat -ConfigPath config\jobs.json -DryRun
scripts\create_pipeline_jobs.bat -ConfigPath config\jobs.json
scripts\start_jenkins.bat
scripts\healthcheck_jenkins.bat
```

停止 Jenkins：

```bat
scripts\stop_jenkins.bat
```

## macOS 使用

macOS 直接使用原生 Shell，不依赖 PowerShell：

```bash
chmod +x scripts/macos/*.sh
./scripts/macos/create_pipeline_jobs.sh --config ./config/jobs.json --dry-run
./scripts/macos/create_pipeline_jobs.sh --config ./config/jobs.json
./scripts/macos/start_jenkins.sh
./scripts/macos/healthcheck_jenkins.sh
```

停止 Jenkins：

```bash
./scripts/macos/stop_jenkins.sh
```

默认配置：

```text
Windows JENKINS_HOME=%USERPROFILE%\.jenkins-infra
macOS JENKINS_HOME=$HOME/.jenkins-infra
端口=8080
监听地址=127.0.0.1
```

## Job 配置

复制 `config/jobs.example.json` 的条目到本地 `config/jobs.json`，填写实际 SVN 地址和 Jenkins 凭据 ID。`config/jobs.json` 已被 Git 忽略，凭据本身只在 Jenkins Credentials 中维护，不写入仓库。

Job 使用 `Pipeline script from SCM` 模式。每个 Job 的 SVN 地址和 Jenkinsfile 路径由配置文件指定，Jenkins 自动分配工作区，不使用开发人员工作副本，也不设置 `customWorkspace`。

首次启动前先生成 Job 配置。已有 Jenkins 实例更新 Job 配置时，先停止 Jenkins，再生成配置，最后重新启动，确保 Jenkins 加载最新的 `config.xml`。

创建远程 SVN 运维目录或提交前，需要先确认 SVN 管理员提供的仓库 URL 和提交权限。本地目录的生成不等于远程 SVN 仓库已经创建。
