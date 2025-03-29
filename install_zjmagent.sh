#!/bin/sh
set -eu

echo "============================================"
echo "ZJM Agent 安装程序"
echo "============================================"

# 1. 检查并安装 pip、python-socketio 和 psutil（仅适用于基于 Debian/Ubuntu 的系统）
if ! command -v pip >/dev/null 2>&1; then
    echo "[INFO] pip 未安装，正在安装 pip..."
    apt-get update && apt-get install -y python3-pip
fi

echo "[INFO] 正在安装 python-socketio 和 psutil..."
pip install --no-cache-dir python-socketio psutil

# 2. 提示用户输入必要信息（无默认值，保留示例提示）
echo -n "请输入服务器ID (例如 DMIT): "
read SERVER_ID
if [ -z "$SERVER_ID" ]; then
    echo "错误：服务器ID不能为空！"
    exit 1
fi

echo -n "请输入身份验证令牌 (例如 bd9fe6d8bd277851ccb57faf06ef81f5): "
read -s TOKEN
echo ""
if [ -z "$TOKEN" ]; then
    echo "错误：身份验证令牌不能为空！"
    exit 1
fi

echo -n "请输入 WebSocket URL (例如 http://192.168.0.1:8008): "
read WS_URL
if [ -z "$WS_URL" ]; then
    echo "错误：WebSocket URL不能为空！"
    exit 1
fi

echo -n "请输入 Dashboard URL (例如 http://192.168.0.1:8000): "
read DASHBOARD_URL
if [ -z "$DASHBOARD_URL" ]; then
    echo "错误：Dashboard URL不能为空！"
    exit 1
fi

echo -n "请输入数据采集间隔（秒，默认 1 秒）: "
read INTERVAL
if [ -z "$INTERVAL" ]; then
    INTERVAL=1
fi

echo -n "请输入监控网卡接口（多个接口用逗号分隔，默认自动选择流量最大的接口）: "
read INTERFACE
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(python -c "import psutil; counters = psutil.net_io_counters(pernic=True); print(max(counters, key=lambda k: counters[k].bytes_sent + counters[k].bytes_recv))")
fi

echo "============================================"
echo "[INFO] 启动参数："
echo "  服务器ID: $SERVER_ID"
echo "  身份验证令牌: $TOKEN"
echo "  WebSocket URL: $WS_URL"
echo "  Dashboard URL: $DASHBOARD_URL"
echo "  数据采集间隔: ${INTERVAL}s"
echo "  网卡接口: $INTERFACE"
echo "============================================"
echo "正在启动 ZJM Agent 容器..."

# 3. 启动 Docker 容器（agent 为客户端，上报数据，不需要端口映射）
container_id=$(docker run -d --name zjmagent \
  vpsbuy/zjmagent:latest \
  --server-id "$SERVER_ID" \
  --token "$TOKEN" \
  --ws-url "$WS_URL" \
  --dashboard-url "$DASHBOARD_URL" \
  --interval "$INTERVAL" \
  --interface "$INTERFACE")

echo "容器已启动，容器ID: $container_id"
echo "============================================"
echo "安装完成。你可以使用以下命令查看容器日志："
echo "docker logs zjmagent"
