下面提供完整的内容，包含单条 docker run 命令模版和 docker-compose 配置模版，并附有相关说明。

---

## 一、单条 docker run 命令模版

### 1. zjmagent

使用 host 网络模式启动 zjmagent，并传入各项参数。  
请根据实际情况替换尖括号内的参数值。

```sh
docker run -d --name zjmagent --net=host vpsbuy/zjmagent:latest --server-id <SERVER_ID> --token <TOKEN> --ws-url <WS_URL> --dashboard-url <DASHBOARD_URL> --interval <INTERVAL> --interface <INTERFACE>
```

**说明**  
- `--net=host` 表示容器将直接使用宿主机的网络。  
- 参数 `--server-id`、`--token`、`--ws-url`、`--dashboard-url`、`--interval`、`--interface` 依次为服务器标识、验证令牌、WebSocket URL、Dashboard URL、数据采集间隔以及网卡接口。

### 2. zjmapp

使用环境变量注入 MySQL 相关信息，并通过端口映射将宿主机端口映射到容器内部端口 8008。  
请替换尖括号内的实际参数值。

```sh
docker run -d --name zjmapp -e MYSQL_HOST=<MYSQL_HOST> -e MYSQL_PORT=<MYSQL_PORT> -e MYSQL_DB=<MYSQL_DB> -e MYSQL_USER=<MYSQL_USER> -e MYSQL_PASSWORD=<MYSQL_PASSWORD> -p <APP_PORT>:8008 vpsbuy/zjmapp:latest
```

**说明**  
- 环境变量 `MYSQL_HOST`、`MYSQL_PORT`、`MYSQL_DB`、`MYSQL_USER`、`MYSQL_PASSWORD` 分别代表 MySQL 主机地址、端口、数据库名称、用户名和密码。  
- `<APP_PORT>` 为宿主机上映射到容器内部 8008 端口的端口号。

---

## 二、docker-compose 配置模版

以下分别给出 zjmagent 和 zjmapp 的 docker-compose 文件配置，每个文件独立提供说明。

### 1. zjmagent 的 docker-compose 配置

```yaml
version: '3'
services:
  zjmagent:
    image: vpsbuy/zjmagent:latest
    container_name: zjmagent
    network_mode: host
    command: ["--server-id", "<SERVER_ID>",
              "--token", "<TOKEN>",
              "--ws-url", "<WS_URL>",
              "--dashboard-url", "<DASHBOARD_URL>",
              "--interval", "<INTERVAL>",
              "--interface", "<INTERFACE>"]
    restart: unless-stopped
```

**说明**  
- 此配置使用 `network_mode: host` 使容器共享宿主机网络。  
- `command` 数组将参数传递给容器中预设的入口程序（例如 Dockerfile 中配置了 ENTRYPOINT）。  
- 请替换 `<SERVER_ID>`、`<TOKEN>`、`<WS_URL>`、`<DASHBOARD_URL>`、`<INTERVAL>`、`<INTERFACE>` 为实际参数。  
- `restart: unless-stopped` 表示容器除非手动停止，否则在异常退出后会自动重启。

### 2. zjmapp 的 docker-compose 配置

```yaml
version: '3'
services:
  zjmapp:
    image: vpsbuy/zjmapp:latest
    container_name: zjmapp
    ports:
      - "<APP_PORT>:8008"
    environment:
      MYSQL_HOST: "<MYSQL_HOST>"
      MYSQL_PORT: "<MYSQL_PORT>"
      MYSQL_DB: "<MYSQL_DB>"
      MYSQL_USER: "<MYSQL_USER>"
      MYSQL_PASSWORD: "<MYSQL_PASSWORD>"
    restart: unless-stopped
```

**说明**  
- 此配置通过 `ports` 将宿主机 `<APP_PORT>` 映射到容器内部的 8008 端口。  
- 通过 `environment` 传入 MySQL 数据库的连接信息。  
- 请替换 `<APP_PORT>`、`<MYSQL_HOST>`、`<MYSQL_PORT>`、`<MYSQL_DB>`、`<MYSQL_USER>`、`<MYSQL_PASSWORD>` 为实际值。  
- 同样设置了 `restart: unless-stopped` 重启策略。

---

以上就是完整的单条 docker 命令和 docker-compose 模版配置，以及相应的说明。请根据您的部署环境和实际需求进行参数替换和调整。
