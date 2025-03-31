下面分别给出 zjmagent 和 zjmapp 的一行 docker run 命令模版，以及基于 YAML 格式的 docker-compose 配置模版，您可以根据实际情况替换尖括号内的参数值。

---

## 一、单条 docker run 命令模版

### 1. zjmagent

```sh
docker run -d --name zjmagent --net=host vpsbuy/zjmagent:latest --server-id <SERVER_ID> --token <TOKEN> --ws-url <WS_URL> --dashboard-url <DASHBOARD_URL> --interval <INTERVAL> --interface <INTERFACE>
```

> **说明**  
> - 使用 `--net=host` 共享宿主机网络。
> - 参数 `<SERVER_ID>`、`<TOKEN>`、`<WS_URL>`、`<DASHBOARD_URL>`、`<INTERVAL>`、`<INTERFACE>` 请根据实际情况替换。

### 2. zjmapp

```sh
docker run -d --name zjmapp -e MYSQL_HOST=<MYSQL_HOST> -e MYSQL_PORT=<MYSQL_PORT> -e MYSQL_DB=<MYSQL_DB> -e MYSQL_USER=<MYSQL_USER> -e MYSQL_PASSWORD=<MYSQL_PASSWORD> -p <APP_PORT>:8008 vpsbuy/zjmapp:latest
```

> **说明**  
> - `<APP_PORT>` 为宿主机映射到容器内 8008 端口的端口号。
> - 环境变量 `<MYSQL_HOST>`、`<MYSQL_PORT>`、`<MYSQL_DB>`、`<MYSQL_USER>`、`<MYSQL_PASSWORD>` 根据实际 MySQL 配置替换。

---

## 二、docker-compose 配置模版

下面给出一个包含两个服务的 docker-compose 示例，其中 zjmagent 的 command 参数使用数组形式传递参数，符合您给出的格式要求：

```yaml
version: '3'
services:
  zjmagent:
    image: vpsbuy/zjmagent:latest
    container_name: zjmagent
    command: ["--server-id", "<SERVER_ID>",
              "--token", "<TOKEN>",
              "--ws-url", "<WS_URL>",
              "--dashboard-url", "<DASHBOARD_URL>",
              "--interval", "<INTERVAL>",
              "--interface", "<INTERFACE>"]
    restart: unless-stopped

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

> **说明**  
> - 对于 **zjmagent**，command 数组形式更清晰、避免解析问题；请替换尖括号中的各项参数。  
> - 对于 **zjmapp**，通过 `ports` 暴露端口，通过 `environment` 注入 MySQL 相关变量。  
> - 如有需要，可以将两个服务分离到不同的 docker-compose 文件中，或根据场景调整网络模式和其他配置。

这两个模版提供了灵活的部署方式，您可根据实际需求选择使用单条 docker 命令或 docker-compose 方式进行部署。
