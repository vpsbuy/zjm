下面分别给出 zjmagent 和 zjmapp 的一行 docker 命令模版以及 docker-compose 配置模版示例，您可以根据实际情况替换尖括号内的参数值。

⸻

一、单条 docker run 命令模版

1. zjmagent 模版

docker run -d --name zjmagent --net=host vpsbuy/zjmagent:latest --server-id <SERVER_ID> --token <TOKEN> --ws-url <WS_URL> --dashboard-url <DASHBOARD_URL> --interval <INTERVAL> --interface <INTERFACE>

说明
	•	使用 --net=host 可让容器共享宿主机网络（如果不需要，可去掉该参数）。
	•	参数 <SERVER_ID>、<TOKEN>、<WS_URL>、<DASHBOARD_URL>、<INTERVAL>、<INTERFACE> 请根据实际情况替换。

2. zjmapp 模版

docker run -d --name zjmapp -e MYSQL_HOST=<MYSQL_HOST> -e MYSQL_PORT=<MYSQL_PORT> -e MYSQL_DB=<MYSQL_DB> -e MYSQL_USER=<MYSQL_USER> -e MYSQL_PASSWORD=<MYSQL_PASSWORD> -p <APP_PORT>:8008 vpsbuy/zjmapp:latest

说明
	•	其中 <APP_PORT> 为主机映射到容器内 8008 端口的端口号。
	•	环境变量 <MYSQL_HOST>、<MYSQL_PORT>、<MYSQL_DB>、<MYSQL_USER>、<MYSQL_PASSWORD> 根据实际 MySQL 信息替换。

⸻

二、docker-compose 配置模版

以下示例将两个服务放在同一个 compose 文件中，您也可以分开配置。

version: '3'
services:
  zjmagent:
    image: vpsbuy/zjmagent:latest
    container_name: zjmagent
    network_mode: host
    command: >
      --server-id <SERVER_ID>
      --token <TOKEN>
      --ws-url <WS_URL>
      --dashboard-url <DASHBOARD_URL>
      --interval <INTERVAL>
      --interface <INTERFACE>
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

说明
	•	对于 zjmagent，使用 network_mode: host 实现与宿主机网络共享；如果不需要可将其删除，并相应调整参数传递。
	•	对于 zjmapp，使用 ports 暴露主机端口，环境变量中替换为实际的 MySQL 信息。
	•	参数 <SERVER_ID>、<TOKEN>、<WS_URL>、<DASHBOARD_URL>、<INTERVAL>、<INTERFACE>、<APP_PORT>、<MYSQL_HOST>、<MYSQL_PORT>、<MYSQL_DB>、<MYSQL_USER>、<MYSQL_PASSWORD> 均请根据实际情况替换。
	•	这里设置了容器重启策略 restart: unless-stopped，可根据需要调整。

⸻

这两个模版均可直接作为基础配置，结合实际部署场景进行相应调整。
