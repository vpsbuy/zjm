#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent.sh
# 交互式安装/管理 炸酱面探针Agent 服务脚本（支持 systemd/OpenRC/手动）
# 演示网址：https://zjm.net
############################################

# 平台检测：仅允许 Linux, macOS, WSL/Git-Bash
OS="$(uname -s)"
if [[ ! "$OS" =~ ^(Linux|Darwin|MINGW|MSYS) ]]; then
  echo "⚠️ 当前系统 $OS 不支持本脚本，请在 Linux/macOS/WSL 或 Git Bash 下运行。"
  exit 1
fi

# 必须以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️ 请以 root 或 sudo 权限运行此脚本"
  exit 1
fi

# 前缀/颜色（避免使用红色）
YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

# 下载根地址（直接下载不同架构二进制，无需压缩包）
AGENT_BASE_URL="https://app.zjm.net"

# 服务名与路径
SERVICE_NAME="zjmagent"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$PROJECT_DIR/agent"
AGENT_BIN="$AGENT_DIR/agent"   # 最终要执行的文件

# CLI 模式及参数
CLI_MODE=0
SERVER_ID=""; TOKEN=""; WS_URL=""; DASHBOARD_URL=""; INTERVAL=1; INTERFACE=""

# ----------------------------
# 安装依赖：curl unzip；Alpine 跳过 systemd
# ----------------------------
install_deps(){
  echo -e "${BLUE}>> 检测并安装依赖：curl unzip${NC}"
  if   command -v apt-get >/dev/null; then
    apt-get update && apt-get install -y curl unzip
  elif command -v yum     >/dev/null; then
    yum install -y curl unzip
  elif command -v dnf     >/dev/null; then
    dnf install -y curl unzip
  elif command -v pacman  >/dev/null; then
    pacman -Sy --noconfirm curl unzip
  elif command -v apk     >/dev/null; then
    apk add --no-cache curl unzip
  else
    echo -e "${YELLOW}❌ 无法识别包管理器，请手动安装 curl 和 unzip${NC}"
    exit 1
  fi
}

# ----------------------------
# 写入 systemd 单元
# ----------------------------
write_systemd_service(){
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
# 写入 OpenRC 服务脚本（Alpine 等）
# ----------------------------
write_openrc_service(){
  cat > "$OPENRC_SERVICE_FILE" <<'EOF'
#!/sbin/openrc-run
name="zjmagent"
description="炸酱面探针Agent"
command="{{AGENT_BIN}}"
command_args="--server-id {{SERVER_ID}} --token {{TOKEN}} --ws-url \"{{WS_URL}}\" --dashboard-url \"{{DASHBOARD_URL}}\" --interval {{INTERVAL}} --interface \"{{INTERFACE}}\""
command_background=true
directory="{{AGENT_DIR}}"
pidfile="/var/run/${RC_SVCNAME}.pid"
start_pre() {
  checkpath --directory --mode 0755 {{AGENT_DIR}}
}
EOF
  sed -i \
    -e "s|{{AGENT_BIN}}|$AGENT_BIN|g" \
    -e "s|{{SERVER_ID}}|$SERVER_ID|g" \
    -e "s|{{TOKEN}}|$TOKEN|g" \
    -e "s|{{WS_URL}}|$WS_URL|g" \
    -e "s|{{DASHBOARD_URL}}|$DASHBOARD_URL|g" \
    -e "s|{{INTERVAL}}|$INTERVAL|g" \
    -e "s|{{INTERFACE}}|$INTERFACE|g" \
    -e "s|{{AGENT_DIR}}|$AGENT_DIR|g" \
    "$OPENRC_SERVICE_FILE"
  chmod +x "$OPENRC_SERVICE_FILE"
  rc-update add "$SERVICE_NAME" default
  rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
}

# ----------------------------
# 安装并启动 Agent
# ----------------------------
do_install(){
  echo -e "${BLUE}>>> 安装并启动 炸酱面探针Agent <<<${NC}"

  install_deps
  mkdir -p "$AGENT_DIR"

  # 1) 判断是否 Alpine（/etc/os-release 中 ID=alpine 或 apk 包管理器）
  if grep -qiE '^ID=alpine' /etc/os-release 2>/dev/null || command -v apk >/dev/null; then
    BINARY_NAME="agent-alpine"
  else
    # 2) 非 Alpine，再根据 CPU 架构选 agent 或 agent-arm
    case "$(uname -m)" in
      x86_64)    BINARY_NAME="agent"      ;;
      aarch64|armv7*|armv8*) BINARY_NAME="agent-arm" ;;
      *) echo -e "${YELLOW}❌ 不支持的架构: $(uname -m)${NC}"; exit 1 ;;
    esac
  fi

  DOWNLOAD_URL="${AGENT_BASE_URL}/${BINARY_NAME}"
  echo -e "${BLUE}>> 下载二进制：${DOWNLOAD_URL}${NC}"
  curl -fsSL "$DOWNLOAD_URL" -o "$AGENT_DIR/agent" || {
    echo -e "${YELLOW}❌ 下载失败，请检查网络或 URL：$DOWNLOAD_URL${NC}"
    exit 1
  }
  chmod +x "$AGENT_DIR/agent"
  AGENT_BIN="$AGENT_DIR/agent"

  # 交互或 CLI 参数
  if [[ $CLI_MODE -eq 0 ]]; then
    read -r -p "请输入服务器唯一标识（server_id）： " SERVER_ID
    read -r -p "请输入令牌（token）： " TOKEN
    read -r -p "请输入 WebSocket 地址（ws-url）： " WS_URL
    read -r -p "请输入主控地址（dashboard-url）： " DASHBOARD_URL
    read -r -p "请输入采集间隔（秒，默认 ${INTERVAL}）： " tmp
    INTERVAL="${tmp:-$INTERVAL}"
  fi

  # 网卡接口
  DEFAULT_IFACE="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
  if [[ $CLI_MODE -eq 1 && -n "$INTERFACE" ]]; then
    echo -e "${BLUE}CLI 模式，使用指定网卡接口：${INTERFACE}${NC}"
  else
    if [[ -n "$DEFAULT_IFACE" ]]; then
      read -r -p "检测到默认网卡接口 ${DEFAULT_IFACE}，是否使用？(Y/n) " yn
      if [[ "$yn" =~ ^[Nn]$ ]]; then
        read -r -p "请输入网卡接口： " INTERFACE
      else
        INTERFACE="$DEFAULT_IFACE"
      fi
    else
      read -r -p "未检测到网卡接口，请输入： " INTERFACE
    fi
  fi

  # 启动服务
  if command -v systemctl >/dev/null 2>&1; then
    write_systemd_service
    echo -e "${GREEN}✅ 使用 systemd 管理，安装并启动完成${NC}"
  elif command -v rc-update >/dev/null 2>&1; then
    write_openrc_service
    echo -e "${GREEN}✅ 使用 OpenRC 管理，安装并启动完成${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到服务管理器，请手动后台运行："
    echo -e "${YELLOW}  cd $AGENT_DIR && nohup $AGENT_BIN --server-id $SERVER_ID --token $TOKEN --ws-url \"$WS_URL\" --dashboard-url \"$DASHBOARD_URL\" --interval $INTERVAL --interface \"$INTERFACE\" &${NC}"
    echo -e "${GREEN}✅ 二进制已就绪，请自行集成到服务或后台启动方案${NC}"
  fi
}

# ----------------------------
# 停止/重启/卸载
# ----------------------------
do_stop(){
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}.service" || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" stop || true
  else
    echo -e "${YELLOW}⚠️ 无法检测到服务管理器，请手动停止进程${NC}"
    return
  fi
  echo -e "${GREEN}✅ 服务已停止${NC}"
}
do_restart(){
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "${SERVICE_NAME}.service"
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
  else
    echo -e "${YELLOW}⚠️ 无法检测到服务管理器，请手动重启进程${NC}"
    return
  fi
  echo -e "${GREEN}✅ 服务已重启${NC}"
}
do_uninstall(){
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload
  elif command -v rc-update >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    rc-update del "$SERVICE_NAME" default 2>/dev/null || true
    rm -f "$OPENRC_SERVICE_FILE"
  else
    echo -e "${YELLOW}⚠️ 无法检测到服务管理器，请手动移除启动脚本或后台进程${NC}"
    return
  fi
  echo -e "${GREEN}✅ 服务已卸载${NC}"
}

# ----------------------------
# CLI 参数解析
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

# CLI 模式且齐全则直接安装
if [[ $CLI_MODE -eq 1 && -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]; then
  do_install
  exit 0
fi

# 交互式菜单前显示状态
echo
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active --quiet "${SERVICE_NAME}.service" \
    && echo -e "${GREEN}服务（systemd）状态：运行中${NC}" \
    || echo -e "${YELLOW}服务（systemd）状态：未运行${NC}"
elif command -v rc-service >/dev/null 2>&1; then
  rc-service "$SERVICE_NAME" status >/dev/null 2>&1 \
    && echo -e "${GREEN}服务（OpenRC）状态：运行中${NC}" \
    || echo -e "${YELLOW}服务（OpenRC）状态：未运行或未配置${NC}"
else
  echo -e "${YELLOW}⚠️ 未检测到服务管理器，可能需手动启动${NC}"
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
  1) do_install   ;;
  2) do_stop      ;;
  3) do_restart   ;;
  4) do_uninstall ;;
  5) echo "退出。"; exit 0 ;;
  *) echo "无效选项"; exit 1 ;;
esac
