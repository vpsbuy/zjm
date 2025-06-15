#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent.sh
# 交互式安装/管理 炸酱面探针Agent 服务脚本
# 演示网址：https://zjm.net
############################################

# 平台检测：仅允许 Linux, macOS, WSL/Git-Bash
OS="$(uname -s)"
if [[ ! "$OS" =~ ^(Linux|Darwin|MINGW|MSYS) ]]; then
  echo "❌ 当前系统 $OS 不支持本脚本，请在 Linux/macOS/WSL 或 Git Bash 下运行。"
  exit 1
fi

# 必须以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 或 sudo 权限运行此脚本"
  exit 1
fi

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Agent 包 URL（请替换为实际地址）
AGENT_ZIP_URL="https://app.zjm.net/agent.zip"

# 服务名与路径
SERVICE_NAME="zjmagent"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$PROJECT_DIR/agent"
AGENT_BIN="$AGENT_DIR/agent"

# CLI 模式标志及参数初始化
CLI_MODE=0
SERVER_ID=""; TOKEN=""; WS_URL=""; DASHBOARD_URL=""; INTERVAL=1; INTERFACE=""

# ----------------------------
# 安装依赖：curl unzip systemd
# ----------------------------
install_deps(){
  echo -e "${BLUE}>> 检测并安装依赖：curl unzip systemd${NC}"
  if   command -v apt-get >/dev/null; then
    apt-get update && apt-get install -y curl unzip systemd
  elif command -v yum     >/dev/null; then
    yum install -y curl unzip systemd
  elif command -v dnf     >/dev/null; then
    dnf install -y curl unzip systemd
  elif command -v pacman  >/dev/null; then
    pacman -Sy --noconfirm curl unzip systemd
  elif command -v apk     >/dev/null; then
    apk add --no-cache curl unzip systemd
  else
    echo -e "${RED}❌ 无法识别包管理器，请手动安装 curl unzip systemd${NC}"
    exit 1
  fi
}

# ----------------------------
# 安装并启动 Agent
# ----------------------------
do_install(){
  echo -e "${BLUE}>>> 安装并启动 炸酱面探针Agent <<<${NC}"

  install_deps

  echo -e "${BLUE}>> 下载并解压 agent.zip → ${AGENT_DIR}${NC}"
  mkdir -p "$AGENT_DIR"
  curl -fsSL "$AGENT_ZIP_URL" -o /tmp/agent.zip
  unzip -o /tmp/agent.zip -d "$AGENT_DIR" -x "agent.log"
  rm -f /tmp/agent.zip

  if [ ! -f "$AGENT_BIN" ]; then
    echo -e "${RED}❌ 找不到 $AGENT_BIN${NC}"
    exit 1
  fi
  chmod +x "$AGENT_BIN"

  # 参数模式下不提示，使用 CLI 参数；交互模式下再询问
  if [[ $CLI_MODE -eq 0 ]]; then
    read -r -p "请输入服务器唯一标识（server_id）： " SERVER_ID
    read -r -p "请输入令牌（token）： " TOKEN
    read -r -p "请输入 WebSocket 地址（ws-url）： " WS_URL
    read -r -p "请输入主控地址（dashboard-url）： " DASHBOARD_URL
    read -r -p "请输入采集间隔（秒，默认 ${INTERVAL}）： " tmp
    INTERVAL="${tmp:-$INTERVAL}"
  fi

  # 网卡接口：参数模式默认，不交互；交互模式询问
  DEFAULT_IFACE="$(ip route | awk '/^default/ {print $5; exit}')"
  if [[ $CLI_MODE -eq 1 ]]; then
    INTERFACE="$DEFAULT_IFACE"
    echo -e "${BLUE}CLI 模式，使用默认网卡接口：${INTERFACE}${NC}"
  else
    echo -e "${BLUE}检测到默认网卡接口：${DEFAULT_IFACE}${NC}"
    read -r -p "是否使用该接口？(Y/n) " yn
    if [[ "$yn" =~ ^[Nn]$ ]]; then
      read -r -p "请输入要使用的网卡接口： " INTERFACE
    else
      INTERFACE="$DEFAULT_IFACE"
    fi
  fi

  echo -e "${BLUE}>> 写入 systemd 单元：${SERVICE_FILE}${NC}"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=炸酱面探针Agent
After=network.target

[Service]
Type=simple
WorkingDirectory=$AGENT_DIR
ExecStart=$AGENT_BIN \\
  --server-id $SERVER_ID \\
  --token $TOKEN \\
  --ws-url "$WS_URL" \\
  --dashboard-url "$DASHBOARD_URL" \\
  --interval $INTERVAL \\
  --interface "$INTERFACE"
Restart=always
RestartSec=5
Environment=AGENT_LOG_LEVEL=INFO

[Install]
WantedBy=multi-user.target
EOF

  echo -e "${BLUE}>> 启用并启动服务${NC}"
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"
  systemctl restart "${SERVICE_NAME}.service"

  echo -e "${GREEN}✅ 安装并启动完成${NC}"
}

# ----------------------------
# 停止/重启/卸载 服务
# ----------------------------
do_stop(){
  echo -e "${BLUE}>> 停止 服务${NC}"
  systemctl stop "${SERVICE_NAME}.service" || true
  echo -e "${GREEN}✅ 已停止${NC}"
}
do_restart(){
  echo -e "${BLUE}>> 重启 服务${NC}"
  systemctl restart "${SERVICE_NAME}.service"
  echo -e "${GREEN}✅ 已重启${NC}"
}
do_uninstall(){
  echo -e "${BLUE}>> 卸载 服务${NC}"
  systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  echo -e "${GREEN}✅ 已卸载${NC}"
}

# ----------------------------
# 解析 CLI 参数（支持非交互安装/停止/重启/卸载）
# ----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-id)     SERVER_ID="$2";     CLI_MODE=1; shift 2;;
    --token)         TOKEN="$2";         CLI_MODE=1; shift 2;;
    --ws-url)        WS_URL="$2";        CLI_MODE=1; shift 2;;
    --dashboard-url) DASHBOARD_URL="$2"; CLI_MODE=1; shift 2;;
    --interval)      INTERVAL="$2";      CLI_MODE=1; shift 2;;
    --interface)     INTERFACE="$2";     CLI_MODE=1; shift 2;;
    stop)            do_stop;            exit 0;;
    restart)         do_restart;         exit 0;;
    uninstall)       do_uninstall;       exit 0;;
    *) break;;
  esac
done

# 如果 CLI 模式且参数齐全，直接安装
if [[ $CLI_MODE -eq 1 && -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]; then
  do_install
  exit 0
fi

# ----------------------------
# 交互式菜单前显示状态
# ----------------------------
echo
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  echo -e "${GREEN}炸酱面探针Agent 服务状态：运行中${NC}"
else
  echo -e "${YELLOW}炸酱面探针Agent 服务状态：未运行${NC}"
fi
echo

# ----------------------------
# 交互式菜单
# ----------------------------
echo -e "${BLUE}请选择操作：${NC}"
echo "1) 安装并启动 Agent"
echo "2) 停止 服务"
echo "3) 重启 服务"
echo "4) 卸载 服务"
echo "5) 退出"
read -r -p "输入 [1-5]: " opt
case "$opt" in
  1) do_install     ;;
  2) do_stop        ;;
  3) do_restart     ;;
  4) do_uninstall   ;;
  5) echo "退出。"; exit 0 ;;
  *) echo "无效选项"; exit 1 ;;
esac
