#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent.sh
# 交互式安装/管理 炸酱面探针Agent 服务脚本
# 支持根据架构/系统自动下载 agent.zip、agent-arm.zip、agent-alpine.zip
# 演示网址：https://zjm.net
############################################

# 平台检测：仅允许 Linux, macOS, WSL/Git-Bash
OS="$(uname -s)"
if [[ ! "$OS" =~ ^(Linux|Darwin|MINGW|MSYS) ]]; then
  echo -e "\033[1;33m⚠️ 当前系统 $OS 不支持本脚本，请在 Linux/macOS/WSL 或 Git Bash 下运行。\033[0m"
  exit 1
fi

# 必须以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m⚠️ 请以 root 或 sudo 权限运行此脚本\033[0m"
  exit 1
fi

# 颜色/前缀
YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

# Agent 包基础 URL 前缀，根据实际情况调整
BASE_AGENT_URL="https://app.zjm.net"

# 服务名与路径
SERVICE_NAME="zjmagent"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
# 若需 OpenRC 可自行扩展
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$PROJECT_DIR/agent"
AGENT_BIN="$AGENT_DIR/agent"

# CLI 模式标志及参数初始化
CLI_MODE=0
SERVER_ID=""; TOKEN=""; WS_URL=""; DASHBOARD_URL=""; INTERVAL=1; INTERFACE=""

# ----------------------------
# 根据架构和发行版选择 ZIP 名称
# ----------------------------
select_agent_zip(){
  ZIP_NAME="agent.zip"
  ARCH="$(uname -m)"
  OS_ID=""
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
  fi

  if [[ "$OS_ID" == "alpine" ]]; then
    ZIP_NAME="agent-alpine.zip"
    echo -e "${BLUE}检测到 Alpine，使用 ZIP: $ZIP_NAME${NC}"
  else
    case "$ARCH" in
      aarch64|armv7l|arm64)
        ZIP_NAME="agent-arm.zip"
        echo -e "${BLUE}检测到 ARM 架构 ($ARCH)，使用 ZIP: $ZIP_NAME${NC}"
        ;;
      x86_64|amd64)
        ZIP_NAME="agent.zip"
        echo -e "${BLUE}检测到 x86_64 架构，使用 ZIP: $ZIP_NAME${NC}"
        ;;
      *)
        ZIP_NAME="agent.zip"
        echo -e "${YELLOW}⚠️ 未识别架构 $ARCH，默认使用 ZIP: $ZIP_NAME，若不合适请手动调整${NC}"
        ;;
    esac
  fi

  AGENT_ZIP_URL="${BASE_AGENT_URL}/${ZIP_NAME}"
  export AGENT_ZIP_URL
}

# ----------------------------
# 安装依赖：curl unzip systemd
# ----------------------------
install_deps(){
  echo -e "${BLUE}>> 检测并安装依赖：curl unzip systemd（若已有则跳过）${NC}"
  if   command -v apt-get >/dev/null; then
    apt-get update
    apt-get install -y curl unzip systemd
  elif command -v yum >/dev/null; then
    yum install -y curl unzip systemd
  elif command -v dnf >/dev/null; then
    dnf install -y curl unzip systemd
  elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm curl unzip systemd
  elif command -v apk >/dev/null; then
    # Alpine 上可能没有 systemd，但安装 unzip/curl
    apk add --no-cache curl unzip || true
  else
    echo -e "${YELLOW}⚠️ 无法识别包管理器，请手动安装 curl 和 unzip${NC}"
    exit 1
  fi
}

# ----------------------------
# 写入 systemd 单元
# ----------------------------
write_systemd_service(){
  echo -e "${BLUE}>> 写入 systemd 单元：${SYSTEMD_SERVICE_FILE}${NC}"
  cat > "$SYSTEMD_SERVICE_FILE" <<EOF
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

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"
  systemctl restart "${SERVICE_NAME}.service"
}

# ----------------------------
# 安装并启动 Agent
# ----------------------------
do_install(){
  echo -e "${BLUE}>>> 安装并启动 炸酱面探针Agent <<<${NC}"

  install_deps

  select_agent_zip

  echo -e "${BLUE}>> 清理旧的安装目录：${AGENT_DIR}${NC}"
  if [[ -d "$AGENT_DIR" ]]; then
    rm -rf "$AGENT_DIR"
  fi
  mkdir -p "$AGENT_DIR"

  echo -e "${BLUE}>> 下载并解压 $AGENT_ZIP_URL → ${AGENT_DIR}${NC}"
  curl -fsSL "$AGENT_ZIP_URL" -o /tmp/agent.zip || {
    echo -e "${YELLOW}⚠️ 下载失败：$AGENT_ZIP_URL，请检查网络或 URL 是否正确${NC}"
    exit 1
  }
  unzip -o /tmp/agent.zip -d "$AGENT_DIR" -x "agent.log" || {
    echo -e "${YELLOW}⚠️ 解压时遇到问题，请检查 agent.zip 内容及 unzip 可用性${NC}"
    exit 1
  }
  rm -f /tmp/agent.zip

  if [ ! -f "$AGENT_BIN" ]; then
    FOUND_BIN=$(find "$AGENT_DIR" -maxdepth 2 -type f -name "agent" | head -n1 || true)
    if [[ -n "$FOUND_BIN" ]]; then
      AGENT_BIN="$FOUND_BIN"
      echo -e "${YELLOW}⚠️ 未在预期路径找到可执行，改用: $AGENT_BIN${NC}"
    else
      echo -e "${YELLOW}⚠️ 找不到 agent 可执行，请检查解压后的文件结构${NC}"
      exit 1
    fi
  fi
  chmod +x "$AGENT_BIN"

  # 获取参数：交互或 CLI
  if [[ $CLI_MODE -eq 0 ]]; then
    read -r -p "请输入服务器唯一标识（server_id）： " SERVER_ID
    read -r -p "请输入令牌（token）： " TOKEN
    read -r -p "请输入 WebSocket 地址（ws-url）： " WS_URL
    read -r -p "请输入主控地址（dashboard-url）： " DASHBOARD_URL
    read -r -p "请输入采集间隔（秒，默认 ${INTERVAL}）： " tmp
    INTERVAL="${tmp:-$INTERVAL}"
  fi

  # 网卡接口选择
  DEFAULT_IFACE="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
  if [[ $CLI_MODE -eq 1 && -n "$INTERFACE" ]]; then
    echo -e "${BLUE}CLI 模式，使用指定网卡接口：${INTERFACE}${NC}"
  else
    if [[ -n "$DEFAULT_IFACE" ]]; then
      echo -e "${BLUE}检测到默认网卡接口：${DEFAULT_IFACE}${NC}"
      read -r -p "是否使用该接口？(Y/n) " yn
      if [[ "$yn" =~ ^[Nn]$ ]]; then
        read -r -p "请输入要使用的网卡接口： " INTERFACE
      else
        INTERFACE="$DEFAULT_IFACE"
      fi
    else
      read -r -p "未检测到默认网卡接口，请输入要使用的网卡接口： " INTERFACE
    fi
  fi

  # 写入并启动 systemd
  echo -e "${BLUE}>> 写入 systemd 单元并启动服务${NC}"
  write_systemd_service
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
  rm -f "$SYSTEMD_SERVICE_FILE"
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

# CLI 参数齐全则直接安装
if [[ $CLI_MODE -eq 1 && -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]; then
  do_install
  exit 0
fi

# 交互式菜单前显示状态
echo
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  echo -e "${GREEN}炸酱面探针Agent 服务状态：运行中${NC}"
else
  echo -e "${YELLOW}炸酱面探针Agent 服务状态：未运行${NC}"
fi
echo

# 交互式菜单
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
  *) echo -e "${YELLOW}无效选项${NC}"; exit 1 ;;
esac
