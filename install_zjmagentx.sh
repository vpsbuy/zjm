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
  if command -v systemctl &>/dev/null; then
    INIT_SYS="systemd"
  elif command -v rc-service &>/dev/null; then
    INIT_SYS="openrc"
  else
    INIT_SYS="none"
  fi
}

install_deps() {
  echo -e "${BLUE}>> 检测并安装依赖：curl unzip iproute2${NC}"
  if command -v apt-get &>/dev/null; then
    if ! apt-get update -qq; then
      if grep -R "buster-backports" /etc/apt/{sources.list,sources.list.d} &>/dev/null; then
        echo -e "${YELLOW}检测到失效的 buster-backports → 注释并降级校验${NC}"
        sed -Ei 's|^deb .+buster-backports.*|# &|' /etc/apt/{sources.list,sources.list.d}/*.list 2>/dev/null || true
        echo 'Acquire::Check-Valid-Until "false";' >/etc/apt/apt.conf.d/99no-check-valid
        apt-get -o Acquire::Check-Valid-Until=false update -qq
      fi
    fi
    apt-get install -y --no-install-recommends curl unzip iproute2
  elif command -v dnf &>/dev/null; then
    dnf install -y curl unzip iproute
  elif command -v yum &>/dev/null; then
    yum install -y curl unzip iproute
  elif command -v pacman &>/dev/null; then
    pacman -Sy --noconfirm curl unzip iproute2
  elif command -v apk &>/dev/null; then
    apk add --no-cache curl unzip openrc iproute2
  else
    echo -e "${YELLOW}无法识别包管理器，请手动安装 curl / unzip${NC}"
    exit 1
  fi
}

create_systemd_unit() {
  cat >"$SERVICE_FILE_SYSTEMD" <<EOF
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
  systemctl enable --now "$SERVICE_NAME"
}

create_openrc_script() {
  cat >"$SERVICE_FILE_OPENRC" <<'EOF'
#!/sbin/openrc-run
description="ZJM Agent"
command="<AGENT_BIN>"
command_args="--server-id <SERVER_ID> --token <TOKEN> --ws-url <WS_URL> \
--dashboard-url <DASHBOARD_URL> --interval <INTERVAL> --interface <INTERFACE>"
command_background=true
pidfile="/run/zjmagent.pid"
EOF
  sed -i \
    -e "s|<AGENT_BIN>|$AGENT_BIN|g" \
    -e "s|<SERVER_ID>|$SERVER_ID|g" \
    -e "s|<TOKEN>|$TOKEN|g" \
    -e "s|<WS_URL>|$WS_URL|g" \
    -e "s|<DASHBOARD_URL>|$DASHBOARD_URL|g" \
    -e "s|<INTERVAL>|$INTERVAL|g" \
    -e "s|<INTERFACE>|$INTERFACE|g"  "$SERVICE_FILE_OPENRC"
  chmod +x "$SERVICE_FILE_OPENRC"
  rc-update add "$SERVICE_NAME" default
  rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
}

do_install() {
  echo -e "${BLUE}>>> 安装并启动 炸酱面探针Agent${NC}"
  detect_init_system
  install_deps

  # 选择对应的 ZIP 包
  ARCH="$(uname -m)"
  if grep -Ei 'alpine' /etc/os-release &>/dev/null; then
    AGENT_ZIP_URL="https://app.zjm.net/agent-alpine.zip"
    echo -e "${BLUE}>> 检测到 Alpine 系统，使用 agent-alpine.zip${NC}"
  elif [[ "$ARCH" == "x86_64" ]]; then
    AGENT_ZIP_URL="https://app.zjm.net/agent.zip"
    echo -e "${BLUE}>> 检测到 x86_64 架构，使用 agent.zip${NC}"
  elif [[ "$ARCH" =~ ^(aarch64|arm64)$ ]]; then
    AGENT_ZIP_URL="https://app.zjm.net/agent-arm.zip"
    echo -e "${BLUE}>> 检测到 ARM 架构，使用 agent-arm.zip${NC}"
  else
    echo -e "${YELLOW}❌ 未知架构：$ARCH，请手动指定 ZIP 包 URL${NC}"
    exit 1
  fi

  # 下载并解压
  echo -e "${BLUE}>> 下载并解压 $AGENT_ZIP_URL → $AGENT_DIR${NC}"
  rm -rf "$AGENT_DIR"
  mkdir -p "$AGENT_DIR"
  curl -fsSL "$AGENT_ZIP_URL" -o /tmp/agent.zip
  unzip -qo /tmp/agent.zip -d "$AGENT_DIR"
  rm -f /tmp/agent.zip

  # 如果解压后只有一个子目录，则剥离一层
  entries=( "$AGENT_DIR"/* )
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
    echo -e "${BLUE}>> 剥离一层嵌套目录：${entries[0]}${NC}"
    mv "${entries[0]}"/* "$AGENT_DIR"/
    rm -rf "${entries[0]}"
  fi

  # 校验并设置可执行权限
  if [[ ! -f "$AGENT_BIN" ]]; then
    echo -e "${YELLOW}❌ 未在 $AGENT_DIR 找到 agent 可执行文件${NC}"
    exit 1
  fi
  chmod +x "$AGENT_BIN"

  # 参数交互
  if [[ $CLI_MODE -eq 0 ]]; then
    read -r -p "服务器唯一标识（server_id）： "  SERVER_ID
    read -r -p "令牌（token）： "                TOKEN
    read -r -p "WebSocket 地址（ws-url）： "     WS_URL
    read -r -p "主控地址（dashboard-url）： "    DASHBOARD_URL
    read -r -p "采集间隔(秒，默认 $INTERVAL)： " tmp && INTERVAL="${tmp:-$INTERVAL}"
  fi

  # 自动探测网卡
  DEFAULT_IFACE=$(
    command -v ip &>/dev/null \
      && ip route | awk '/^default/{print $5;exit}' \
      || ifconfig 2>/dev/null | awk '/flags=/{print $1;exit}' | sed 's/://'
  )
  [[ -z "$DEFAULT_IFACE" ]] && DEFAULT_IFACE="eth0"
  if [[ $CLI_MODE -eq 1 && -n "$INTERFACE" ]]; then
    :
  elif [[ $CLI_MODE -eq 1 ]]; then
    INTERFACE="$DEFAULT_IFACE"
  else
    echo -e "${BLUE}检测到默认网卡：$DEFAULT_IFACE${NC}"
    read -r -p "是否使用该网卡？(Y/n) " yn
    [[ "${yn:-y}" =~ ^[Nn]$ ]] && read -r -p "请输入网卡名： " INTERFACE || INTERFACE="$DEFAULT_IFACE"
  fi

  # 安装为系统服务
  case "$INIT_SYS" in
    systemd) create_systemd_unit ;;
    openrc)  create_openrc_script ;;
    none)
      echo -e "${YELLOW}⚠️  未检测到 systemd/openrc，已跳过服务安装\n手动运行示例：$AGENT_BIN --server-id $SERVER_ID ...${NC}"
      ;;
  esac

  echo -e "${GREEN}✅ Agent 安装完成（Init=$INIT_SYS）${NC}"
}

do_stop()      { detect_init_system; [[ $INIT_SYS == systemd ]] && systemctl stop "$SERVICE_NAME" \
                             || [[ $INIT_SYS == openrc ]] && rc-service "$SERVICE_NAME" stop \
                             || echo -e "${YELLOW}未检测到已安装服务${NC}"; }
do_restart()   { detect_init_system; [[ $INIT_SYS == systemd ]] && systemctl restart "$SERVICE_NAME" \
                             || [[ $INIT_SYS == openrc ]] && rc-service "$SERVICE_NAME" restart \
                             || echo -e "${YELLOW}未检测到已安装服务${NC}"; }
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

# CLI 参数
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

# CLI 一次性安装
if [[ $CLI_MODE -eq 1 && -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]; then
  do_install
  exit 0
fi

# 状态提示
detect_init_system
echo
if [[ $INIT_SYS == systemd ]]; then
  systemctl is-active --quiet "$SERVICE_NAME" \
    && echo -e "${GREEN}炸酱面探针Agent服务状态：运行中${NC}" \
    || echo -e "${YELLOW}炸酱面探针Agent服务状态：未运行${NC}"
elif [[ $INIT_SYS == openrc ]]; then
  rc-service "$SERVICE_NAME" status &>/dev/null \
    && echo -e "${GREEN}炸酱面探针Agent服务状态：运行中${NC}" \
    || echo -e "${YELLOW}炸酱面探针Agent服务状态：未运行${NC}"
else
  echo -e "${YELLOW}未检测到系统服务${NC}"
fi
echo

# 交互菜单
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
