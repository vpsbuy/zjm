下面提供三种主控安装炸酱面探针的方法，包括使用安装脚本、直接使用 Docker 命令以及使用 Docker Compose。

---

## 方法一：使用安装脚本

这种方式适合对命令行操作较熟悉的用户，安装步骤如下：

1. **下载安装脚本**  
   执行以下命令，将安装脚本下载到当前目录：
   ```bash
   curl -fsSL https://raw.githubusercontent.com/vpsbuy/zjm/refs/heads/main/install_zjmapp.sh -o install_zjmapp.sh
   ```

2. **赋予执行权限**  
   给予脚本执行权限：
   ```bash
   chmod +x install_zjmapp.sh
   ```

3. **运行安装脚本**  
   启动脚本以安装炸酱面探针：
   ```bash
   ./install_zjmapp.sh
   ```
   
安装脚本会自动拉取所需的 Docker 镜像并启动容器，你可以随后通过日志或容器状态确认是否安装成功。

---

## 方法二：使用 Docker 命令直接运行

如果你希望手动使用 Docker 命令来安装和启动炸酱面探针，可以参考以下步骤：

1. **运行 Docker 命令**  
   在终端中执行下面的命令，将使用主机网络模式启动一个名为 `zjmapp` 的容器：
   ```bash
   docker run -d \
     --name zjmapp \
     --network host \
     -e MYSQL_HOST=127.0.0.1 \
     -e MYSQL_PORT=3306 \
     -e MYSQL_DB=dashboard \
     -e MYSQL_USER=dashboard \
     -e MYSQL_PASSWORD=6tzAywbmnZP3xiEp \
     vpsbuy/zjmapp:latest && docker logs -f zjmapp
   ```
   - 这里，通过环境变量为容器内部配置了 MySQL 数据库的连接信息；
   - `--network host` 选项表示容器将直接使用主机网络，适用于需要与主机共享网络环境的场景。

2. **查看日志**  
   命令执行后，容器启动的日志会自动输出。也可以单独使用以下命令查看日志：
   ```bash
   docker logs -f zjmapp
   ```

---

## 方法三：使用 Docker Compose

如果你更习惯使用 Docker Compose 来管理容器，可以按照以下步骤操作：

1. **创建 docker-compose 文件**  
   在你喜欢的目录下创建一个名为 `docker-compose.yaml` 的文件，内容如下：
   ```yaml
   version: "3"
   services:
     zjmapp:
       image: vpsbuy/zjmapp:latest
       container_name: zjmapp
       network_mode: host
       environment:
         - MYSQL_HOST=127.0.0.1
         - MYSQL_PORT=3306
         - MYSQL_DB=dashboard
         - MYSQL_USER=dashboard
         - MYSQL_PASSWORD=6tzAywbmnZP3xiEp
   ```

2. **启动服务**  
   打开终端，进入到 `docker-compose.yaml` 所在的目录，然后执行以下命令：
   ```bash
   docker-compose up -d
   ```

3. **查看日志**  
   你可以使用下面的命令查看容器启动后的日志：
   ```bash
   docker-compose logs -f zjmapp
   ```

---

## 小结

- **方法一（安装脚本）**：适合快速安装，只需简单的下载、赋权和执行操作。  
- **方法二（直接 Docker 命令）**：适合熟悉 Docker 命令行操作的用户，允许手动配置容器选项。  
- **方法三（Docker Compose）**：适合日后容器管理和编排，可通过 Compose 文件集中管理服务配置。

根据您的需求和使用习惯选择合适的方法即可。安装完成后，请根据实际情况检查容器运行状态，并确保 MySQL 数据库服务可正常访问。
