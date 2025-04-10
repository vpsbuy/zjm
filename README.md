# 一、下面提供三种主控安装炸酱面探针的方法，包括使用安装脚本、直接使用 Docker 命令以及使用 Docker Compose，请预先配置好mysql。

---

## 方法一：使用安装脚本

1. **下载脚本**  
   使用以下命令下载安装脚本：
   ```bash
   curl -fsSL https://raw.githubusercontent.com/vpsbuy/zjm/refs/heads/main/install_zjmapp.sh -o install_zjmapp.sh
   ```

2. **赋予权限**  
   赋予脚本执行权限：
   ```bash
   chmod +x install_zjmapp.sh
   ```

3. **运行脚本**  
   执行安装脚本：
   ```bash
   ./install_zjmapp.sh
   ```
   脚本会自动拉取镜像并启动容器，根据提示输入信息，安装完成后可通过日志检查运行状态。

---

## 方法二：直接使用 Docker run 命令

将 Compose 中的配置转换为 Docker run 命令，执行以下命令启动主控容器：
```bash
docker run -d \
  --name zjmapp \
  --network host \
  --restart unless-stopped \
  -e MYSQL_HOST=127.0.0.1 \
  -e MYSQL_PORT=3306 \
  -e MYSQL_DB=dashboard \
  -e MYSQL_USER=dashboard \
  -e MYSQL_PASSWORD=6tzAywbmnZP3xiEp \
  -e APP_PORT=9009 \
  vpsbuy/zjmapp:latest
```
使用此命令，容器会通过主机网络模式运行，并按需自动重启。可通过 `docker logs -f zjmapp` 查看启动日志。

---

## 方法三：使用 Docker Compose

1. **创建 Compose 文件**  
   在任一目录下创建 `docker-compose.yaml`，内容如下：
   ```yaml
   version: "3"
   services:
     zjmapp:
       image: vpsbuy/zjmapp:latest
       container_name: zjmapp
       network_mode: host
       restart: unless-stopped
       environment:
         - MYSQL_HOST=127.0.0.1
         - MYSQL_PORT=3306
         - MYSQL_DB=dashboard
         - MYSQL_USER=dashboard
         - MYSQL_PASSWORD=6tzAywbmnZP3xiEp
         - APP_PORT=9009
   ```

2. **启动服务**  
   进入 `docker-compose.yaml` 所在目录，执行：
   ```bash
   docker-compose up -d
   ```

3. **查看日志**  
   使用下面命令跟踪容器日志：
   ```bash
   docker-compose logs -f zjmapp
   ```

---

### 小结

- **安装脚本**：简单快速，适合需手动配置参数的场景。  
- **Docker run 命令**：适合直接使用命令行启动，参数清晰直接。  
- **Docker Compose**：便于日后维护和统一管理配置，推荐用于生产环境部署。

请根据自身需求和实际环境选择合适的安装方法，安装完成后记得检查日志以确认主控服务正常运行。

# 二、下面提供炸酱面探针 agent 的三种安装方法，分别是使用安装脚本、使用 Docker run 命令以及使用 Docker Compose 管理。根据你的需求，可以选择适合自己情况的方法安装 agent。

---

## 方法一：使用安装脚本

这种方式简单直接，通过运行安装脚本完成 agent 安装。

1. **下载安装脚本**  
   在终端执行以下命令，将安装脚本下载到当前目录：
   ```bash
   curl -fsSL https://raw.githubusercontent.com/vpsbuy/zjm/refs/heads/main/install_zjmagent.sh -o install_zjmagent.sh
   ```

2. **赋予执行权限**  
   为脚本赋予执行权限：
   ```bash
   chmod +x install_zjmagent.sh
   ```

3. **运行安装脚本**  
   通过执行脚本启动安装：
   ```bash
   ./install_zjmagent.sh
   ```

安装脚本会自动拉取对应的 Docker 镜像并启动 agent，安装后可以通过日志确认运行状态。

---

## 方法二：使用 Docker run 命令

根据方法三的 Docker Compose 配置，可以转换为 Docker run 命令。具体操作如下：

1. **使用 Docker run 命令**  
   执行以下命令启动 agent 容器：
   ```bash
   docker run -d \
     --restart unless-stopped \
     --name zjmagent \
     --network host \
     vpsbuy/zjmagent:latest \
     --server-id agent \
     --token 7675b4c33323625d25f7158120f53354 \
     --ws-url http://1.1.1.1:8008 \
     --dashboard-url http://1.1.1.1:8008 \
     --interval 1 \
     --interface eth0
   ```
   - 参数说明：
     - `--restart unless-stopped`：确保容器在异常退出后自动重启。
     - `--network host`：使用主机网络模式，确保网络通信顺畅。
     - 后面的参数按照 compose 文件中的 command 配置传递，完成 agent 的初始化参数设置。

2. **查看容器日志**  
   如果需要查看容器运行状态，可执行：
   ```bash
   docker logs -f zjmagent
   ```

---

## 方法三：使用 Docker Compose

利用 Docker Compose 可以更方便地管理和配置容器。步骤如下：

1. **创建 docker-compose 文件**  
   在你希望运行 agent 的目录下创建一个名为 `docker-compose.yaml` 的文件，文件内容如下：
   ```yaml
   version: "3"
   services:
     zjmagent:
       image: vpsbuy/zjmagent:latest
       container_name: zjmagent
       network_mode: host
       command: ["--server-id", "agent",
                 "--token", "7675b4c33323625d25f7158120f53354",
                 "--ws-url", "http://1.1.1.1:8008",
                 "--dashboard-url", "http://1.1.1.1:8008",
                 "--interval", "1",
                 "--interface", "eth0"]
       restart: unless-stopped
   ```

2. **启动服务**  
   打开终端，进入到 `docker-compose.yaml` 所在目录，然后执行以下命令启动 agent 容器：
   ```bash
   docker-compose up -d
   ```

3. **查看容器日志**  
   通过以下命令可以实时查看容器日志，确认 agent 状态：
   ```bash
   docker-compose logs -f zjmagent
   ```

---

## 小结

- **方法一（安装脚本）**：简单快速，适合不想手动配置 Docker 的用户。  
- **方法二（Docker run 命令）**：直接使用命令行启动容器，适合习惯命令行操作的用户；命令中已包含所有启动参数。  
- **方法三（Docker Compose）**：适用于需要长期维护和管理的场景，通过 Compose 文件可以集中管理多个容器和配置项。

选择合适的方法进行安装后，请确认 agent 与服务器之间的网络配置正常，以及相关依赖（如 Docker、Docker Compose）已正确安装。

# 三、以下是注意事项：

- **核查网卡名称**：默认使用 `eth0`，实际系统中可能不同，请使用 `ip addr` 或 `ifconfig` 检查，并根据实际情况调整 agent 的 `--interface` 参数。

- **Host 网络模式**：使用 `--network host` 后，容器共享宿主机网络。确保指定的接口为实际监控目标。

- **多网卡环境**：若宿主机有多个网卡，确认只监控期望的那一个，防止遗漏或错误统计流量。

- **网络权限与防火墙**：确保防火墙设置允许 agent 与服务器（ws-url、dashboard-url）正常通信。

- **变动响应**：如系统网络配置变化（网卡名称、IP 等），及时更新 agent 配置，保持监控数据准确。
