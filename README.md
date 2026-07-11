# CI Infrastructure

本目录维护跨项目 Jenkins 实例的启停、健康检查和 Pipeline Job 配置，不依赖任何 Unity 工程。

## 目录

```text
jenkins-infra/
├── config/
│   ├── jobs.json              本地配置，不提交
│   └── jobs.example.json      公共示例
├── scripts/
│   ├── windows/
│   │   ├── start_jenkins.bat
│   │   ├── start_jenkins.ps1
│   │   ├── stop_jenkins.bat
│   │   ├── stop_jenkins.ps1
│   │   ├── healthcheck_jenkins.bat
│   │   ├── healthcheck_jenkins.ps1
│   │   ├── create_pipeline_jobs.bat
│   │   ├── create_pipeline_jobs.ps1
│   │   ├── check_prerequisites.bat
│   │   ├── check_prerequisites.ps1
│   │   ├── install_prerequisites.bat
│   │   └── install_prerequisites.ps1
│   └── macos/
│       ├── start_jenkins.sh
│       ├── stop_jenkins.sh
│       ├── healthcheck_jenkins.sh
│       ├── create_pipeline_jobs.sh
│       ├── check_prerequisites.sh
│       └── install_prerequisites.sh
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
scripts\windows\create_pipeline_jobs.bat -ConfigPath config\jobs.json -DryRun
scripts\windows\create_pipeline_jobs.bat -ConfigPath config\jobs.json
scripts\windows\start_jenkins.bat
scripts\windows\healthcheck_jenkins.bat
```

检查和安装 Java 17：

```bat
scripts\windows\check_prerequisites.bat
scripts\windows\install_prerequisites.bat
```

安装脚本默认询问用户；也可以显式使用 `install_prerequisites.bat -Java` 或 `-WhatIf`。

停止 Jenkins：

```bat
scripts\windows\stop_jenkins.bat
```

## macOS 使用

macOS 直接使用原生 Shell，不依赖 PowerShell：

```bash
./scripts/macos/check_prerequisites.sh
./scripts/macos/install_prerequisites.sh
chmod +x scripts/macos/*.sh
./scripts/macos/create_pipeline_jobs.sh --config ./config/jobs.json --dry-run
./scripts/macos/create_pipeline_jobs.sh --config ./config/jobs.json
./scripts/macos/start_jenkins.sh
./scripts/macos/healthcheck_jenkins.sh
```

安装脚本默认逐项询问；也可以使用 `./scripts/macos/install_prerequisites.sh --all` 或先加 `--dry-run` 预览命令。

停止 Jenkins：

```bash
./scripts/macos/stop_jenkins.sh
```

默认配置：

```text
Windows/macOS JENKINS_HOME=<CIInfrastructure目录>/scripts/.jenkins
端口=8080
监听地址=127.0.0.1
```

默认 Jenkins Home 是 `scripts/.jenkins`，也可以修改，但必须在启动和停止时使用同一个目录。Windows 示例：

```bat
scripts\windows\start_jenkins.bat -JenkinsHome D:\JenkinsHome
scripts\windows\stop_jenkins.bat -JenkinsHome D:\JenkinsHome
```

macOS 示例：

```bash
./scripts/macos/start_jenkins.sh --jenkins-home "$HOME/JenkinsHome"
JENKINS_HOME="$HOME/JenkinsHome" ./scripts/macos/stop_jenkins.sh
```

建议将 Jenkins Home 放在项目仓库之外，并确保运行账号对该目录有读写权限。

## Jenkins 管理员和用户

当前启动脚本默认使用 `-Djenkins.install.runSetupWizard=false`，因此首次启动不会自动创建管理员，实例初始状态为不需要登录。首次配置管理员时，只能在本机访问 Jenkins 的情况下执行以下操作：

1. 启动 Jenkins，打开 `http://127.0.0.1:8080/script`。
2. 将下面脚本中的用户名和密码替换为实际值后执行。密码只在本次操作中输入，不要提交到 Git、README、Jenkinsfile 或启动脚本。

```groovy
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.Jenkins

def jenkins = Jenkins.get()
def username = "admin"
def password = "请替换为强密码"

def realm = new HudsonPrivateSecurityRealm(false)
jenkins.setSecurityRealm(realm)
realm.createAccount(username, password)

def authorization = new FullControlOnceLoggedInAuthorizationStrategy()
authorization.setAllowAnonymousRead(false)
jenkins.setAuthorizationStrategy(authorization)
jenkins.save()

println "管理员创建完成，请重新登录。"
```

3. 打开 `http://127.0.0.1:8080/login`，使用刚创建的账号登录。
4. 添加其他用户：`Manage Jenkins` → `Users` → `Create User`。

权限选择建议：

- 所有使用者都是管理员时，可使用 `Logged-in users can do anything`，但不建议用于多人共享实例。
- 有普通用户时，使用 Matrix Authorization Strategy 或 Role-based Authorization Strategy，只给管理员 `Overall/Administer`，普通用户按需授予 `Overall/Read`、`Job/Read`、`Job/Build`、`Job/Workspace` 等权限。
- Jenkins 内置用户数据库适合小型内部 CI；如需统一账号，应改用 LDAP、Active Directory 或其他外部认证插件。

启用认证后，`/script` 也需要管理员权限。Script Console 具备完整系统权限，只应由可信管理员使用；执行前建议备份 `JENKINS_HOME`。Jenkins 的认证和授权由两部分组成：Security Realm 负责用户认证，Authorization Strategy 负责权限分配，详见 [Jenkins 安全配置文档](https://www.jenkins.io/doc/book/security/managing-security/) 和 [用户管理文档](https://www.jenkins.io/doc/book/managing/users/)。

## Job 配置

复制 `config/jobs.example.json` 的条目到本地 `config/jobs.json`，填写实际 SVN 地址和 Jenkins 凭据 ID。`config/jobs.json` 已被 Git 忽略，凭据本身只在 Jenkins Credentials 中维护，不写入仓库。

Job 使用 `Pipeline script from SCM` 模式。每个 Job 的 SVN 地址和 Jenkinsfile 路径由配置文件指定，Jenkins 自动分配工作区，不使用开发人员工作副本，也不设置 `customWorkspace`。

首次启动前先生成 Job 配置。已有 Jenkins 实例更新 Job 配置时，先停止 Jenkins，再生成配置，最后重新启动，确保 Jenkins 加载最新的 `config.xml`。

创建远程 SVN 运维目录或提交前，需要先确认 SVN 管理员提供的仓库 URL 和提交权限。本地目录的生成不等于远程 SVN 仓库已经创建。
