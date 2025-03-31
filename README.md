下面给出完整示例内容，包括单条 docker run 命令和 docker-compose 配置示例，并附有详细说明。其中对于网卡接口参数，说明该参数并不是必须的，可根据实际需求选择传入或让程序自动检测默认网卡。

---

## 一、单条 docker run 命令示例

### 1. zjmagent

示例使用 host 网络模式启动 zjmagent，并传入各项参数。示例参数如下：  
- 服务器 ID：DMIT  
- Token：bd9fe6d8bd277851ccb57faf06ef81f5  
- WebSocket URL 和 Dashboard URL 均为：http://1.1.1.1:8008  
- 数据采集间隔：1  
- 网卡接口：eth0（可选参数，如果不指定，程序可尝试自动检测网卡）

```sh
docker run -d --name zjmagent --net=host vpsbuy/zjmagent:latest --server-id DMIT --token bd9fe6d8bd277851ccb57faf06ef81f5 --ws-url http://1.1.1.1:8008 --dashboard-url http://1.1.1.1:8008 --interval 1 --interface eth0
```

**说明**  
- `--net=host` 表示容器直接使用宿主机网络。  
- 参数依次为：服务器标识、验证令牌、WebSocket URL、Dashboard URL、数据采集间隔和网卡接口。  
- 网卡接口参数不是必须的。如果未指定，程序可以自动选择流量最大的网卡或使用默认接口。

### 2. zjmapp

使用环境变量注入 MySQL 相关信息，并通过端口映射将宿主机端口映射到容器内部的 8008 端口。示例采用以下参数：  
- MySQL 主机：127.0.0.1  
- MySQL 端口：3306  
- MySQL 数据库：zjm_db  
- MySQL 用户名：root  
- MySQL 密码：example  
- 映射端口：8008

```sh
docker run -d --name zjmapp -e MYSQL_HOST=127.0.0.1 -e MYSQL_PORT=3306 -e MYSQL_DB=zjm_db -e MYSQL_USER=root -e MYSQL_PASSWORD=example -p 8008:8008 vpsbuy/zjmapp:latest
```

**说明**  
- 环境变量用于传入 MySQL 数据库连接信息。  
- `<APP_PORT>:8008` 中，8008 为容器内部服务端口，同时将宿主机 8008 映射到容器中。

---

## 二、docker-compose 配置示例

以下分别给出 zjmagent 和 zjmapp 的 docker-compose 文件配置示例，每个文件独立提供说明。

### 1. zjmagent 的 docker-compose 配置

```yaml
version: '3'
services:
  zjmagent:
    image: vpsbuy/zjmagent:latest
    container_name: zjmagent
    network_mode: host
    command: ["--server-id", "DMIT",
              "--token", "bd9fe6d8bd277851ccb57faf06ef81f5",
              "--ws-url", "http://1.1.1.1:8008",
              "--dashboard-url", "http://1.1.1.1:8008",
              "--interval", "1",
              "--interface", "eth0"]
    restart: unless-stopped
```

**说明**  
- `network_mode: host` 确保容器共享宿主机网络。  
- `command` 数组形式传递参数给容器中预设的入口程序。  
- 服务器 ID 已设置为 "DMIT"。  
- 网卡接口参数是可选项。如果您不需要指定特定接口，可以省略该参数，程序会尝试自动选择合适的网卡。  
- `restart: unless-stopped` 表示容器在异常退出后会自动重启，除非手动停止。

### 2. zjmapp 的 docker-compose 配置

```yaml
version: '3'
services:
  zjmapp:
    image: vpsbuy/zjmapp:latest
    container_name: zjmapp
    ports:
      - "8008:8008"
    environment:
      MYSQL_HOST: "127.0.0.1"
      MYSQL_PORT: "3306"
      MYSQL_DB: "zjm_db"
      MYSQL_USER: "root"
      MYSQL_PASSWORD: "example"
    restart: unless-stopped
```

**说明**  
- `ports` 将宿主机的 8008 映射到容器内部的 8008 端口。  
- `environment` 中设置了 MySQL 数据库的连接信息。  
- 同样采用 `restart: unless-stopped` 重启策略。

---

以上即为完整示例内容，请根据实际部署环境替换示例中的参数。如果对网卡接口有特定要求，可通过传入 `--interface` 参数指定，否则可以让程序自动选择合适的接口。
