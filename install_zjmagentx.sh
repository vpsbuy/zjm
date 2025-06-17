#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent.sh
# 安装/管理 炸酱面探针Agent 服务脚本（兼容 systemd/OpenRC）
# 三种二进制：agent (amd), agent-arm, agent-alpine
# 安装根固定为 /opt/zjmagent，二进制放 /opt/zjmagent/agent
############################################

OS="$(uname -s)"
if [[ ! "$OS" =~ ^(Linux|Darwin|MINGW|MSYS) ]]; then
  echo "⚠️ 当前系统 $OS 不支持本脚本。"
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️ 请以 root 或 sudo 运行。"
  exit 1
fi

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
BASE_URL="https://app.zjm.net"
SERVICE_NAME="zjmagent"

SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"

INSTALL_ROOT="/opt/zjmagent"
AGENT_BIN="$INSTALL_ROOT/agent"

CLI_MODE=0
SERVER_ID=""; TOKEN=""; WS_URL=""; DASHBOARD_URL=""; INTERVAL=1; INTERFACE=""

install_deps(){
  echo -e "${BLUE}>> 安装依赖 curl${NC}"
  if   command -v apt-get >/dev/null; then apt-get update && apt-get install -y curl
  elif command -v yum     >/dev/null; then yum install -y curl
  elif command -v dnf     >/dev/null; then dnf install -y curl
  elif command -v pacman  >/dev/null; then pacman -Sy --noconfirm curl
  elif command -v apk     >/dev/null; then apk add --no-cache curl
  else
    echo -e "${YELLOW}❌ 无法识别包管理器，请手动安装 curl${NC}"
    exit 1
  fi
}

write_systemd_service(){
  cat > "$SYSTEMD_SERVICE_FILE" <<EOF
[Unit]
Description=炸酱面探针Agent
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_ROOT
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
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

write_openrc_service(){
  cat > "$OPENRC_SERVICE_FILE" <<EOF
#!/sbin/openrc-run
name="$SERVICE_NAME"
description="炸酱面探针Agent"

command="$AGENT_BIN"
command_args="--server-id $SERVER_ID --token $TOKEN --ws-url \\"$WS_URL\\" --dashboard-url \\"$DASHBOARD_URL\\" --interval $INTERVAL --interface \\"$INTERFACE\\""

PIDFILE="/var/run/$SERVICE_NAME.pid"

command_background=true
directory="$INSTALL_ROOT"

depend() {
  need net
}

start_pre() {
  checkpath --directory --mode 0755 "$INSTALL_ROOT"
}

start() {
  ebegin "Starting $SERVICE_NAME"
  start-stop-daemon --start --background --make-pidfile --pidfile "\${PIDFILE}" --exec "\${command}" -- \${command_args}
  eend $?
}

stop() {
  ebegin "Stopping $SERVICE_NAME"
  start-stop-daemon --stop --pidfile "\${PIDFILE}" --retry 5
  rm -f "\${PIDFILE}"
  eend $?
}

status() {
  status_of_proc -p "\${PIDFILE}" "\${command}" "$SERVICE_NAME"
}
EOF
  chmod +x "$OPENRC_SERVICE_FILE"
  rc-update add "$SERVICE_NAME" default
  rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
}

do_install(){
  echo -e "${BLUE}>>> 安装并启动 Agent <<<${NC}"
  install_deps

  mkdir -p "$INSTALL_ROOT"
  chmod 755 "$INSTALL_ROOT"

  # 选取对应二进制
  ARCH="$(uname -m)"
  IS_ALPINE=0
  grep -qi alpine /etc/os-release 2>/dev/null && IS_ALPINE=1
  if   [[ $IS_ALPINE -eq 1 ]]; then FILE=agent-alpine
  elif [[ $ARCH == x86_64 ]];   then FILE=agent
  elif [[ $ARCH == aarch64 ]];  then FILE=agent-arm
  else
    echo -e "${YELLOW}❌ 不支持架构: $ARCH${NC}"
    exit 1
  fi

  URL="$BASE_URL/$FILE"
  TMP=\$(mktemp)
  curl -fSL "\$URL" -o "\$TMP" || {
    echo -e "${YELLOW}❌ 下载失败: \$URL${NC}"
    exit 1
  }
  mv "\$TMP" "\$AGENT_BIN"
  chmod +x "\$AGENT_BIN"

  # 交互或 CLI 参数读取
  if [[ \$CLI_MODE -eq 0 ]]; then
    read -p "server_id: "     SERVER_ID
    read -p "token: "         TOKEN
    read -p "ws-url: "        WS_URL
    read -p "dashboard-url: " DASHBOARD_URL
    read -p "interval(秒)[1]: " tmp
    INTERVAL=\${tmp:-1}
  fi

  # 网卡
  DEF_IF=\$(ip route 2>/dev/null|awk '/^default/{print\$5;exit}')
  if [[ \$CLI_MODE -eq 1 && -n \$INTERFACE ]];then
    :
  elif [[ -n \$DEF_IF ]]; then
    read -p "Use interface \$DEF_IF ?(Y/n): " yn
    [[ \$yn =~ ^[Nn] ]] && read -p "iface: " INTERFACE || INTERFACE=\$DEF_IF
  else
    read -p "iface: " INTERFACE
  fi

  # 写服务脚本并启动
  if command -v systemctl &>/dev/null; then
    write_systemd_service
  elif command -v rc-update &>/dev/null; then
    write_openrc_service
  else
    echo -e "${YELLOW}⚠️ 无 systemd/OpenRC，请手动后台运行${NC}"
  fi

  echo -e "${GREEN}✅ 安装完成${NC}"
}

do_stop(){
  if command -v systemctl &>/dev/null; then systemctl stop "$SERVICE_NAME"
  else rc-service "$SERVICE_NAME" stop; fi
}
do_restart(){
  if command -v systemctl &>/dev/null; then systemctl restart "$SERVICE_NAME"
  else rc-service "$SERVICE_NAME" restart; fi
}
do_uninstall(){
  if command -v systemctl &>/dev/null; then
    systemctl disable "$SERVICE_NAME"
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload
  else
    rc-service "$SERVICE_NAME" stop
    rc-update del "$SERVICE_NAME" default
    rm -f "$OPENRC_SERVICE_FILE"
  fi
  echo -e "${GREEN}✅ 已卸载${NC}"
}

# 解析 CLI
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-id)     SERVER_ID="$2";CLI_MODE=1;shift 2;;
    --token)         TOKEN="$2";CLI_MODE=1;shift 2;;
    --ws-url)        WS_URL="$2";CLI_MODE=1;shift 2;;
    --dashboard-url) DASHBOARD_URL="$2";CLI_MODE=1;shift 2;;
    --interval)      INTERVAL="$2";CLI_MODE=1;shift 2;;
    --interface)     INTERFACE="$2";CLI_MODE=1;shift 2;;
    stop)            do_stop;exit 0;;
    restart)         do_restart;exit 0;;
    uninstall)       do_uninstall;exit 0;;
    *) break;;
  esac
done

if [[ $CLI_MODE -eq 1 && -n $SERVER_ID && -n $TOKEN && -n $WS_URL && -n $DASHBOARD_URL ]];then
  do_install;exit 0
fi

echo "1) install & start"
echo "2) stop"
echo "3) restart"
echo "4) uninstall"
echo "5) exit"
read -p "Choose[1-5]: " opt
case "$opt" in
  1) do_install ;;
  2) do_stop    ;;
  3) do_restart ;;
  4) do_uninstall ;;
  *) exit 0     ;;
esac
