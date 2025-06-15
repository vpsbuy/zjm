#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent.sh · 2025-06-15
# 炸酱面探针 Agent 安装 / 管理 脚本
############################################

# ───────────── 平台 / 权限 ──────────────
OS="$(uname -s)"
if [[ ! "$OS" =~ ^(Linux|Darwin|MINGW|MSYS) ]]; then
  echo "❌ 仅支持 Linux / macOS / WSL / Git-Bash，当前：$OS"
  exit 1
fi
[[ $EUID -eq 0 ]] || { echo "⚠️  请使用 root / sudo 运行"; exit 1; }

# ───────────── 颜色（无红色） ────────────
YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

# ───────────── 变量 ─────────────────────
AGENT_ZIP_URL="https://app.zjm.net/agent.zip"
SERVICE_NAME="zjmagent"
SERVICE_FILE_SYSTEMD="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_FILE_OPENRC="/etc/init.d/${SERVICE_NAME}"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$PROJECT_DIR/agent"
AGENT_BIN="$AGENT_DIR/agent"

CLI_MODE=0
SERVER_ID=""; TOKEN=""; WS_URL=""; DASHBOARD_URL=""; INTERVAL=1; INTERFACE=""
INIT_SYS="unknown"   # systemd | openrc | none

# ───────────── 函数 ─────────────────────
detect_init_system() {
  if command -v systemctl &>/dev/null;  then INIT_SYS="systemd"
  elif command -v rc-service &>/dev/null; then INIT_SYS="openrc"
  else INIT_SYS="none"; fi
}

install_deps() {
  echo -e "${BLUE}>> 检测并安装依赖${NC}"
  if command -v apt-get &>/dev/null; then
    # Debian/Ubuntu
    apt-get update -qq
    apt-get install -y --no-install-recommends curl unzip iproute2
  elif command -v dnf &>/dev/null; then
    dnf install -y curl unzip iproute
  elif command -v yum &>/dev/null; then
    yum install -y curl unzip iproute
  elif command -v pacman &>/dev/null; then
    pacman -Sy --noconfirm curl unzip iproute2
  elif command -v apk &>/dev/null; then
    echo -e "${BLUE}>> Alpine Linux: 安装 curl unzip openrc iproute2 glibc 兼容层${NC}"
    # 基础包
    apk add --no-cache curl unzip openrc iproute2
    # 安装 glibc 兼容包 (sgerrand)
    wget -q -O /etc/apk/keys/sgerrand.rsa.pub \
      https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
    GLIBC_VER="2.35-r1"
    curl -LsS "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-${GLIBC_VER}.apk" \
         -o "/tmp/glibc-${GLIBC_VER}.apk"
    curl -LsS "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-bin-${GLIBC_VER}.apk" \
         -o "/tmp/glibc-bin-${GLIBC_VER}.apk"
    apk add --no-cache --allow-untrusted \
      /tmp/glibc-${GLIBC_VER}.apk \
      /tmp/glibc-bin-${GLIBC_VER}.apk
    rm -f /tmp/glibc-*.apk
  else
    echo -e "${YELLOW}无法识别包管理器，请手动安装 curl / unzip${NC}"
    exit 1
  fi
}

create_systemd_unit() {
  mkdir -p /var/log
  cat >"$SERVICE_FILE_SYSTEMD" <<EOF
[Unit]
Description=炸酱面探针Agent
After=network.target network-online.target

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
StandardOutput=append:/var/log/${SERVICE_NAME}.log
StandardError=append:/var/log/${SERVICE_NAME}.err
Environment=AGENT_LOG_LEVEL=INFO

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
}

create_openrc_script() {
  mkdir -p /var/log
  cat >"$SERVICE_FILE_OPENRC" <<EOF
#!/sbin/openrc-run
description="炸酱面探针Agent"
depend() {
    need net
}

# 使用 glibc loader 启动
command="/usr/glibc-compat/lib/ld-linux-x86-64.so.2"
command_args="$AGENT_BIN \\
  --server-id $SERVER_ID \\
  --token $TOKEN \\
  --ws-url $WS_URL \\
  --dashboard-url $DASHBOARD_URL \\
  --interval $INTERVAL \\
  --interface $INTERFACE"

pidfile="/run/${SERVICE_NAME}.pid"
command_background=true
output_log="/var/log/${SERVICE_NAME}.log"
error_log="/var/log/${SERVICE_NAME}.err"
EOF

  chmod +x "$SERVICE_FILE_OPENRC"
  rc-update add "$SERVICE_NAME" default
  rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
}

do_install() {
  echo -e "${BLUE}>>> 安装并启动 炸酱面探针Agent${NC}"
  detect_init_system
  install_deps

  echo -e "${BLUE}>> 下载并解压 agent.zip → $AGENT_DIR${NC}"
  mkdir -p "$AGENT_DIR"
  curl -fsSL "$AGENT_ZIP_URL" -o /tmp/agent.zip
  unzip -qo /tmp/agent.zip -d "$AGENT_DIR"
  rm -f /tmp/agent.zip
  [[ -f "$AGENT_BIN" ]] || { echo -e "${YELLOW}❌ 找不到 $AGENT_BIN${NC}"; exit 1; }
  chmod +x "$AGENT_BIN"

  # ── 参数补全 ──────────────────────────
  if [[ $CLI_MODE -eq 0 ]]; then
    read -r -p "服务器唯一标识（server_id）： "  SERVER_ID
    read -r -p "令牌（token）： "               TOKEN
    read -r -p "WebSocket 地址（ws-url）： "    WS_URL
    read -r -p "主控地址（dashboard-url）： "   DASHBOARD_URL
    read -r -p "采集间隔(秒，默认 $INTERVAL)： " tmp && INTERVAL="${tmp:-$INTERVAL}"
  fi

  # ── 网卡选择 ───────────────────────────
  DEFAULT_IFACE=$(ip route 2>/dev/null | awk '/^default/{print $5;exit}')
  [[ -z "$DEFAULT_IFACE" ]] && DEFAULT_IFACE="eth0"
  if [[ $CLI_MODE -eq 1 && -n "$INTERFACE" ]]; then
    : # 已由参数指定
  elif [[ $CLI_MODE -eq 1 ]]; then
    INTERFACE="$DEFAULT_IFACE"
  else
    echo -e "${BLUE}检测到默认网卡：$DEFAULT_IFACE${NC}"
    read -r -p "是否使用该网卡？(Y/n) " yn
    if [[ "${yn:-y}" =~ ^[Nn]$ ]]; then
      read -r -p "请输入网卡名： " INTERFACE
    else
      INTERFACE="$DEFAULT_IFACE"
    fi
  fi

  # ── 安装服务 ───────────────────────────
  case "$INIT_SYS" in
    systemd) create_systemd_unit ;;
    openrc)  create_openrc_script ;;
    none)
      echo -e "${YELLOW}⚠️ 未检测到 systemd/openrc，已跳过服务安装${NC}"
      echo "手动运行示例：$AGENT_BIN --server-id $SERVER_ID ...";;
  esac

  echo -e "${GREEN}✅ Agent 安装完成（Init=$INIT_SYS）${NC}"
}

do_stop() {
  detect_init_system
  if [[ $INIT_SYS == systemd ]]; then
    systemctl stop "$SERVICE_NAME"
  elif [[ $INIT_SYS == openrc ]]; then
    rc-service "$SERVICE_NAME" stop
  else
    echo -e "${YELLOW}未检测到已安装服务${NC}"
  fi
}

do_restart() {
  detect_init_system
  if [[ $INIT_SYS == systemd ]]; then
    systemctl restart "$SERVICE_NAME"
  elif [[ $INIT_SYS == openrc ]]; then
    rc-service "$SERVICE_NAME" restart
  else
    echo -e "${YELLOW}未检测到已安装服务${NC}"
  fi
}

do_uninstall() {
  detect_init_system
  if [[ $INIT_SYS == systemd ]]; then
    systemctl disable --now "$SERVICE_NAME" || true
    rm -f "$SERVICE_FILE_SYSTEMD"
    systemctl daemon-reload
  elif [[ $INIT_SYS == openrc ]]; then
    rc-service "$SERVICE_NAME" stop || true
    rc-update del "$SERVICE_NAME" default || true
    rm -f "$SERVICE_FILE_OPENRC"
  fi
  echo -e "${GREEN}✅ 已卸载 Agent${NC}"
}

# ───────────── CLI 参数 ────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-id)     SERVER_ID="$2";     CLI_MODE=1; shift 2 ;;
    --token)         TOKEN="$2";         CLI_MODE=1; shift 2 ;;
    --ws-url)        WS_URL="$2";        CLI_MODE=1; shift 2 ;;
    --dashboard-url) DASHBOARD_URL="$2"; CLI_MODE=1; shift 2 ;;
    --interval)      INTERVAL="$2";      CLI_MODE=1; shift 2 ;;
    --interface)     INTERFACE="$2";     CLI_MODE=1; shift 2 ;;
    stop)            do_stop;      exit 0 ;;
    restart)         do_restart;   exit 0 ;;
    uninstall)       do_uninstall; exit 0 ;;
    *) break ;;
  esac
done

# 一次性全参数安装
if [[ $CLI_MODE -eq 1 && -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]; then
  do_install; exit 0
fi

# ───────────── 状态 & 菜单 ─────────────
detect_init_system
echo
if [[ $INIT_SYS == systemd ]]; then
  systemctl is-active --quiet "$SERVICE_NAME" && \
    echo -e "${GREEN}${SERVICE_NAME} 服务状态：运行中${NC}" || \
    echo -e "${YELLOW}${SERVICE_NAME} 服务状态：未运行${NC}"
elif [[ $INIT_SYS == openrc ]]; then
  rc-service "$SERVICE_NAME" status &>/dev/null && \
    echo -e "${GREEN}${SERVICE_NAME} 服务状态：运行中${NC}" || \
    echo -e "${YELLOW}${SERVICE_NAME} 服务状态：未运行${NC}"
else
  echo -e "${YELLOW}未检测到系统服务${NC}"
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
  1) do_install   ;;
  2) do_stop      ;;
  3) do_restart   ;;
  4) do_uninstall ;;
  5) echo "退出"; exit 0 ;;
  *) echo "无效选项"; exit 1 ;;
esac
