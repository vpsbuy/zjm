# 一、炸酱面探针在线demo
[https://zjm.net/](https://zjm.net)
# 二、炸酱面探针界面预览
![OsQVIM.md.jpg](https://ooo.0x0.ooo/2025/06/15/OsQVIM.md.jpg) ![OsQdNc.md.jpg](https://ooo.0x0.ooo/2025/06/15/OsQdNc.md.jpg)

![OsQfFG.md.jpg](https://ooo.0x0.ooo/2025/06/15/OsQfFG.md.jpg) ![OsQsEr.md.jpg](https://ooo.0x0.ooo/2025/06/15/OsQsEr.md.jpg)

# 三、炸酱面探针安装方法
## 一、下面提供主控安装炸酱面探针的方法，包括使用直接使用 Docker 命令以及使用 Docker Compose。

---

- **提示1**：安装完主控后，请在日志中查看后台 admin 密码。

![OsQlR1.jpg](https://ooo.0x0.ooo/2025/06/15/OsQlR1.jpg)

- **提示2**：安装完成后访问 http://IP:9009 或者 安装时的端口，也可以用域名反代后访问。  
---

### 方法一：直接使用 Docker run 命令

直接使用 Docker 命令启动主控容器，操作步骤如下：

1. **运行 Docker 命令**  
   执行以下命令（请根据需要修改环境变量的值）：
   ```bash
   docker run -d \
     --name zjmapp \
     --network host \
     --restart unless-stopped \
     -e APP_PORT=9009 \
     vpsbuy/zjmapp:latest
   ```

2. **查看日志并确认**  
   启动后，通过以下命令查看日志：
   ```bash
   docker logs -f zjmapp
   ```
   日志中将包含后台 admin 密码信息。

3. **注意事项**  
   - 请确保日志中记录的 admin 密码已正确保存。  
   - APP_PORT=9009 可自行设置端口号。 
---

### 方法二：使用 Docker Compose

利用 Docker Compose 文件方便统一管理和后期维护，操作步骤如下：

1. **创建 Compose 文件**  
   在任一目录下创建名为 `docker-compose.yaml` 的文件，内容如下：
   ```yaml
   services:
     zjmapp:
       image: vpsbuy/zjmapp:latest
       container_name: zjmapp
       network_mode: host
       restart: unless-stopped
       environment:
         - APP_PORT=9009
   ```

2. **启动服务**  
   进入 `docker-compose.yaml` 所在目录，执行：
   ```bash
   docker-compose up -d
   ```

3. **查看日志**  
   使用以下命令查看日志，确认后台 admin 密码及运行状态：
   ```bash
   docker-compose logs -f zjmapp
   ```

4. **注意事项**  
   - 请确保日志中记录的 admin 密码已正确保存。  
   - APP_PORT=9009 可自行设置端口号。

---

### 选择适合您情况的安装方法后，按照上述步骤进行部署。安装完成后，请务必参考日志中提示内容，确保后台 admin 密码已查看并妥善保存。

## 二、下面提供炸酱面探针 agent 的三种安装方法，分别是使用管理面板agent一键安装代码、使用安装脚本以及使用 Docker Compose 管理。根据你的需求，可以选择适合自己情况的方法安装 agent。


---
## 方法一：使用管理面板一键生成的agent安装代码(推荐)

![OsQ99I.md.jpg](https://ooo.0x0.ooo/2025/06/15/OsQ99I.md.jpg)
---
### 后续可运行agent脚本进行重启卸载等操作
   ```bash
   ./install_zjmagent.sh
   ```

### 方法二：使用安装脚本

通过运行安装脚本完成 agent 安装。

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

### 按照提示输入对应内容，安装后请确认运行状态。

---

## 方法三：使用 Docker Compose

利用 Docker Compose 可以更方便地管理和配置容器。步骤如下：

1. **创建 docker-compose 文件**  
   在你希望运行 agent 的目录下创建一个名为 `docker-compose.yaml` 的文件，文件内容如下：
   ```yaml
   services:
     zjmagent:
       image: vpsbuy/zjmagent:latest
       container_name: zjmagent
       network_mode: host
       command: ["--server-id", "agent",
                 "--token", "7675b4c33323625d25f7158120f53354",
                 "--ws-url", "http://1.1.1.1:8008",
                 "--dashboard-url", "http://1.1.1.1:8008",
                 "--interval", "1"
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

选择合适的方法进行安装后，请确认 agent 与服务器之间的网络配置正常，以及相关依赖（如 Docker、Docker Compose）已正确安装。

# 四、以下是注意事项：

- **核查网卡名称**：默认使用 `eth0`，实际系统中可能不同，请使用 `ip addr` 或 `ifconfig` 检查，并根据实际情况调整 agent 的 `--interface` 参数。

- **Host 网络模式**：使用 `--network host` 后，容器共享宿主机网络。确保指定的接口为实际监控目标。

- **多网卡环境**：若宿主机有多个网卡，确认只监控期望的那一个，防止遗漏或错误统计流量。

- **网络权限与防火墙**：确保防火墙设置允许 agent 与服务器（ws-url、dashboard-url）正常通信。

- **变动响应**：如系统网络配置变化（网卡名称、IP 等），及时更新 agent 配置，保持监控数据准确。
