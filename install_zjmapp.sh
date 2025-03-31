#!/bin/sh
set -eu

echo "============================================"
echo "ZJM App 安装程序"
echo "============================================"

# 检查 docker 是否已安装
if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] docker 命令不存在，请先安装 Docker。"
    exit 1
fi

# 提示用户输入 MySQL 相关信息，并校验非空
while true; do
    echo -n "请输入 MySQL 主机地址: "
    read MYSQL_HOST
    if [ -n "$MYSQL_HOST" ]; then
        break
    else
        echo "错误：MySQL 主机地址不能为空！"
    fi
done

while true; do
    echo -n "请输入 MySQL 端口 (例如 3306): "
    read MYSQL_PORT
    if [ -n "$MYSQL_PORT" ]; then
        break
    else
        echo "错误：MySQL 端口不能为空！"
    fi
done

while true; do
    echo -n "请输入 MySQL 数据库名称: "
    read MYSQL_DB
    if [ -n "$MYSQL_DB" ]; then
        break
    else
        echo "错误：MySQL 数据库名称不能为空！"
    fi
done

while true; do
    echo -n "请输入 MySQL 用户名: "
    read MYSQL_USER
    if [ -n "$MYSQL_USER" ]; then
        break
    else
        echo "错误：MySQL 用户名不能为空！"
    fi
done

while true; do
    echo -n "请输入 MySQL 密码: "
    read -s MYSQL_PASSWORD
    echo ""
    if [ -n "$MYSQL_PASSWORD" ]; then
        break
    else
        echo "错误：MySQL 密码不能为空！"
    fi
done

# 提示用户输入主机映射端口（容器内部为 8008），若为空则默认使用 8008
echo -n "请输入主机端口映射 (默认使用 8008): "
read APP_PORT
if [ -z "$APP_PORT" ]; then
    APP_PORT=8008
fi

echo "============================================"
echo "[INFO] 配置参数："
echo "  MySQL 主机: $MYSQL_HOST"
echo "  MySQL 端口: $MYSQL_PORT"
echo "  MySQL 数据库: $MYSQL_DB"
echo "  MySQL 用户: $MYSQL_USER"
echo "  主机端口映射: $APP_PORT -> 8008 (容器内部)"
echo "============================================"
echo "正在启动容器..."

# 运行 docker 容器，并捕获容器 ID
container_id=$(docker run -d \
  -e MYSQL_HOST="$MYSQL_HOST" \
  -e MYSQL_PORT="$MYSQL_PORT" \
  -e MYSQL_DB="$MYSQL_DB" \
  -e MYSQL_USER="$MYSQL_USER" \
  -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
  -p "$APP_PORT:8008" \
  vpsbuy/zjmapp:latest)

# 检查容器是否成功启动
if [ -z "$container_id" ]; then
    echo "[ERROR] 容器启动失败。"
    exit 1
fi

echo "容器已启动，容器ID: $container_id"
echo "============================================"
echo "等待启动日志输出..."
# 等待一段时间以确保 entrypoint.sh 执行完成，生成 admin_credentials.json 并输出随机密码提示
sleep 5

echo "安装完成。请使用以下命令查看初始管理员凭据（随机生成的密码）："
echo "docker logs $container_id"
