#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent.sh
# 安装/管理 炸酱面探针Agent 服务脚本（兼容 systemd/OpenRC/其它）
# 三种二进制：agent (amd), agent-arm, agent-alpine
# 安装根固定为 /opt/zjmagent
############################################

OS="$(uname -s)"
if [[ ! "$OS" =~ ^(Linux|Darwin|MINGW|MSYS) ]]; then
  echo "⚠️ 当前系统 $OS 不支持本脚本，请在 Linux/macOS/WSL 或 Git Bash 下运行。"
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️ 请以 root 或 sudo 权限运行此脚本"
  exit 1
fi

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
BASE_URL="https://app.zjm.net"
SERVICE_NAME="zjmagent"

SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"

# 固定安装根，二进制和可能的配置文件都放此目录
INSTALL_ROOT="/opt/zjmagent"
AGENT_DIR="$INSTALL_ROOT"
AGENT_BIN="$AGENT_DIR/agent"

CLI_MODE=0
SERVER_ID=""; TOKEN=""; WS_URL=""; DASHBOARD_URL=""; INTERVAL=1; INTERFACE=""

install_deps(){
  echo -e "${BLUE}>> 安装依赖：curl${NC}"
  if command -v apt-get >/dev/null; then
    apt-get update
    apt-get install -y curl
  elif command -v yum >/dev/null; then
    yum install -y curl
  elif command -v dnf >/dev/null; then
    dnf install -y curl
  elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm curl
  elif command -v apk >/dev/null; then
    apk add --no-cache curl
  else
    echo -e "${YELLOW}❌ 无法识别包管理器，请手动安装 curl${NC}"
    exit 1
  fi
}

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

write_openrc_service(){
  echo -e "${BLUE}>> 写入 OpenRC 服务脚本：${OPENRC_SERVICE_FILE}${NC}"
  cat > "$OPENRC_SERVICE_FILE" <<EOF
#!/sbin/openrc-run
name="${SERVICE_NAME}"
description="炸酱面探针Agent"

command="${AGENT_BIN}"
command_args="--server-id ${SERVER_ID} --token ${TOKEN} --ws-url \"${WS_URL}\" --dashboard-url \"${DASHBOARD_URL}\" --interval ${INTERVAL} --interface \"${INTERFACE}\""

PIDFILE="/var/run/${SERVICE_NAME}.pid"

command_background=true
directory="${AGENT_DIR}"

depend() {
  need net
}

start_pre() {
    checkpath --directory --mode 0755 "${AGENT_DIR}"
}

start() {
    ebegin "Starting ${SERVICE_NAME}"
    start-stop-daemon --start --background --make-pidfile --pidfile "${PIDFILE}" --exec "${command}" -- ${command_args}
    eend $?
}

stop() {
    ebegin "Stopping ${SERVICE_NAME}"
    start-stop-daemon --stop --pidfile "${PIDFILE}" --retry 5
    rm -f "${PIDFILE}"
    eend $?
}

status() {
    status_of_proc -p "${PIDFILE}" "${command}" "${SERVICE_NAME}"
}
EOF
  chmod +x "$OPENRC_SERVICE_FILE"
  rc-update add "$SERVICE_NAME" default
  rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
}

do_install(){
  echo -e "${BLUE}>>> 安装并启动 炸酱面探针Agent <<<${NC}"
  install_deps

  echo -e "${BLUE}>> 创建安装目录：${INSTALL_ROOT}${NC}"
  mkdir -p "$AGENT_DIR"
  chmod 755 "$INSTALL_ROOT"

  echo -e "${BLUE}>> 检测架构并下载对应二进制${NC}"
  ARCH="$(uname -m)"
  IS_ALPINE=0
  if [ -f /etc/os-release ] && grep -qi alpine /etc/os-release; then
    IS_ALPINE=1
  fi

  if [[ "$IS_ALPINE" -eq 1 ]]; then
    FILE_NAME="agent-alpine"
  elif [[ "$ARCH" == "x86_64" ]]; then
    FILE_NAME="agent"
  elif [[ "$ARCH" == "aarch64" ]]; then
    FILE_NAME="agent-arm"
  else
    echo -e "${YELLOW}❌ 不支持的架构: $ARCH${NC}"
    exit 1
  fi

  DOWNLOAD_URL="${BASE_URL}/${FILE_NAME}"
  echo -e "${BLUE}>> 从 ${DOWNLOAD_URL} 下载到临时文件${NC}"
  TMP_FILE="$(mktemp)"
  if ! curl -fSL "$DOWNLOAD_URL" -o "$TMP_FILE"; then
    echo -e "${YELLOW}❌ 下载失败，请检查 URL 或网络: $DOWNLOAD_URL${NC}"
    rm -f "$TMP_FILE"
    exit 1
  fi
  echo -e "${BLUE}>> 移动到 ${AGENT_BIN} 并赋可执行权限${NC}"
  if ! mv "$TMP_FILE" "$AGENT_BIN"; then
    echo -e "${YELLOW}❌ 无法移动到 $AGENT_BIN，请检查权限或磁盘${NC}"
    rm -f "$TMP_FILE"
    exit 1
  fi
  chmod +x "$AGENT_BIN"
  echo -e "${GREEN}✅ 二进制已保存：$AGENT_BIN${NC}"

  if [[ $CLI_MODE -eq 0 ]]; then
    read -r -p "请输入服务器唯一标识（server_id）： " SERVER_ID
    read -r -p "请输入令牌（token）： " TOKEN
    read -r -p "请输入 WebSocket 地址（ws-url）： " WS_URL
    read -r -p "请输入主控地址（dashboard-url）： " DASHBOARD_URL
    read -r -p "请输入采集间隔（秒，默认 ${INTERVAL}）： " tmp
    INTERVAL="${tmp:-$INTERVAL}"
  fi

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

  if command -v systemctl >/dev/null && systemctl --version >/dev/null 2>&1; then
    write_systemd_service
    echo -e "${GREEN}✅ 使用 systemd 管理，安装并启动完成${NC}"
  elif command -v rc-update >/dev/null && command -v openrc >/dev/null; then
    write_openrc_service
    echo -e "${GREEN}✅ 使用 OpenRC 管理，安装并启动完成${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC，无法自动配置服务。"
    echo -e "${YELLOW}请手动后台运行："
    echo -e "${YELLOW}  cd $AGENT_DIR && nohup $AGENT_BIN --server-id $SERVER_ID --token $TOKEN --ws-url \"$WS_URL\" --dashboard-url \"$DASHBOARD_URL\" --interval $INTERVAL --interface \"$INTERFACE\" &${NC}"
    echo -e "${GREEN}✅ 二进制和配置已准备，请自行集成到后台启动脚本${NC}"
  fi
}

do_stop(){
  echo -e "${BLUE}>> 停止 服务${NC}"
  if command -v systemctl >/dev/null && systemctl --version >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}.service" || true
    echo -e "${GREEN}✅ systemd 服务已停止${NC}"
  elif command -v rc-service >/dev/null; then
    rc-service "$SERVICE_NAME" stop || true
    echo -e "${GREEN}✅ OpenRC 服务已停止${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC，需手动停止后台进程${NC}"
  fi
}
do_restart(){
  echo -e "${BLUE}>> 重启 服务${NC}"
  if command -v systemctl >/dev/null && systemctl --version >/dev/null 2>&1; then
    systemctl restart "${SERVICE_NAME}.service"
    echo -e "${GREEN}✅ systemd 服务已重启${NC}"
  elif command -v rc-service >/dev/null; then
    rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
    echo -e "${GREEN}✅ OpenRC 服务已重启${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC，需手动重启后台进程${NC}"
  fi
}
do_uninstall(){
  echo -e "${BLUE}>> 卸载 服务${NC}"
  if command -v systemctl >/dev/null && systemctl --version >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${GREEN}✅ 已卸载 systemd 服务${NC}"
  elif command -v rc-update >/dev/null; then
    rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    rc-update del "$SERVICE_NAME" default 2>/dev/null || true
    rm -f "$OPENRC_SERVICE_FILE"
    echo -e "${GREEN}✅ 已卸载 OpenRC 服务脚本${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC，若以前手动启动，请自行停止并移除脚本${NC}"
  fi
}

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

if [[ $CLI_MODE -eq 1 && -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]; then
  do_install
  exit 0
fi

echo
if command -v systemctl >/dev/null && systemctl --version >/dev/null 2>&1; then
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    echo -e "${GREEN}服务状态（systemd）：运行中${NC}"
  else
    echo -e "${YELLOW}服务状态（systemd）：未运行${NC}"
  fi
elif command -v rc-service >/dev/null; then
  if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
    echo -e "${GREEN}服务状态（OpenRC）：运行中${NC}"
  else
    echo -e "${YELLOW}服务状态（OpenRC）：未运行或未配置${NC}"
  fi
else
  echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC 服务管理，可能需手动启动${NC}"
fi
echo

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
