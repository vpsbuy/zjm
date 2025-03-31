#!/bin/sh
set -eu

echo "============================================"
echo "ZJM Agent 安装程序"
echo "============================================"

# 检查 docker 是否已安装
if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] docker 命令不存在，请先安装 Docker。"
    exit 1
fi

# 默认值
INTERVAL=1
INTERFACE=""

# 解析命令行参数
while [ $# -gt 0 ]; do
  case "$1" in
    --server-id)
      SERVER_ID="$2"
      shift 2
      ;;
    --token)
      TOKEN="$2"
      shift 2
      ;;
    --ws-url)
      WS_URL="$2"
      shift 2
      ;;
    --dashboard-url)
      DASHBOARD_URL="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --interface)
      INTERFACE="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

# 如未提供必填参数，则提示用户输入
if [ -z "${SERVER_ID:-}" ]; then
    echo -n "请输入服务器ID (例如 DMIT): "
    read SERVER_ID
    if [ -z "$SERVER_ID" ]; then
        echo "错误：服务器ID不能为空！"
        exit 1
    fi
fi

if [ -z "${TOKEN:-}" ]; then
    echo -n "请输入身份验证令牌: "
    read TOKEN
    echo ""
    if [ -z "$TOKEN" ]; then
        echo "错误：身份验证令牌不能为空！"
        exit 1
    fi
fi

if [ -z "${WS_URL:-}" ]; then
    echo -n "请输入 WebSocket URL (例如 http://192.168.0.1:8008): "
    read WS_URL
    if [ -z "$WS_URL" ]; then
        echo "错误：WebSocket URL不能为空！"
        exit 1
    fi
fi

if [ -z "${DASHBOARD_URL:-}" ]; then
    echo -n "请输入 Dashboard URL (例如 http://192.168.0.1:8000): "
    read DASHBOARD_URL
    if [ -z "$DASHBOARD_URL" ]; then
        echo "错误：Dashboard URL不能为空！"
        exit 1
    fi
fi

# 检查并安装 pip3 及所需的 python 模块（python-socketio 和 psutil）
if ! command -v pip3 >/dev/null 2>&1; then
    echo "[INFO] pip 未安装，正在安装 pip..."
    apt-get update && apt-get install -y python3-pip
fi
echo "[INFO] 正在安装 python-socketio 和 psutil..."
pip3 install --no-cache-dir python-socketio psutil

# 如果未指定网卡接口，则自动选取流量最大的网卡
if [ -z "${INTERFACE:-}" ]; then
    INTERFACE=$(python3 -c "import psutil; counters = psutil.net_io_counters(pernic=True); print(max(counters, key=lambda k: counters[k].bytes_sent + counters[k].bytes_recv))")
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

echo "[INFO] 正在启动 ZJM Agent 容器..."

# 启动 docker 容器，agent 作为客户端不需要端口映射
container_id=$(docker run -d --name zjmagent --net=host \
  vpsbuy/zjmagent:latest \
  --server-id "$SERVER_ID" \
  --token "$TOKEN" \
  --ws-url "$WS_URL" \
  --dashboard-url "$DASHBOARD_URL" \
  --interval "$INTERVAL" \
  --interface "$INTERFACE")

echo "容器已启动，容器ID: $container_id"
echo "============================================"
echo "安装完成。请使用以下命令查看容器日志："
echo "docker logs zjmagent"
