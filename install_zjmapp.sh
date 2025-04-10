#!/bin/bash
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

# 提示用户输入 APP 端口
while true; do
    echo -n "请输入 APP 端口 (例如 9009): "
    read APP_PORT
    if [ -n "$APP_PORT" ]; then
        break
    else
        echo "错误：APP 端口不能为空！"
    fi
done

echo "============================================"
echo "[INFO] 配置参数："
echo "  MySQL 主机: $MYSQL_HOST"
echo "  MySQL 端口: $MYSQL_PORT"
echo "  MySQL 数据库: $MYSQL_DB"
echo "  MySQL 用户: $MYSQL_USER"
echo "  APP 端口: $APP_PORT"
echo "============================================"
echo "正在启动容器..."

# 使用 host 模式运行容器，设置 restart 策略为 unless-stopped，并命名容器为 zjmapp
container_id=$(docker run -d \
  --restart unless-stopped \
  --name zjmapp \
  -e MYSQL_HOST="$MYSQL_HOST" \
  -e MYSQL_PORT="$MYSQL_PORT" \
  -e MYSQL_DB="$MYSQL_DB" \
  -e MYSQL_USER="$MYSQL_USER" \
  -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
  -e APP_PORT="$APP_PORT" \
  --network host \
  vpsbuy/zjmapp:latest)

# 检查容器是否成功启动
if [ -z "$container_id" ]; then
    echo "[ERROR] 容器启动失败。"
    exit 1
fi

echo "容器已启动，容器ID: $container_id"
echo "============================================"
echo "等待启动日志输出..."
# 等待一段时间以确保容器入口程序初始化完成
sleep 5

echo "安装完成。下面输出当前容器日志："
docker logs zjmapp

echo "日志输出完成，程序退出。"
