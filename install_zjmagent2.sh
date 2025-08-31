#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent2.sh
# 交互式安装/管理 炸酱面探针 agent2 服务脚本（systemd / OpenRC / 其它）
# 下载地址：https://app.zjm.net/agent2.zip / agent2-alpine.zip / agent2-arm.zip
############################################

# 平台检测：允许 Linux / macOS / WSL / Git-Bash
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

# 颜色
YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

# 服务名与路径
SERVICE_NAME="zjmagent2"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"

# 项目目录与 Agent 路径
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$PROJECT_DIR/$SERVICE_NAME"
AGENT_BIN="$AGENT_DIR/agent"

# CLI 模式标志及参数（默认：采样 5 秒、推送 30 秒）
CLI_MODE=0
SERVER_ID=""; TOKEN=""; WS_URL=""; DASHBOARD_URL=""
INTERVAL=5
PUSH_INTERVAL=30
INTERFACE=""

##############################
# 安装依赖：curl unzip
##############################
install_deps(){
  echo -e "${BLUE}>> 检测并安装依赖：curl unzip${NC}"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl unzip
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl unzip
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm curl unzip
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl unzip
  elif command -v brew >/dev/null 2>&1; then
    brew install curl unzip
  else
    echo -e "${YELLOW}❌ 无法识别包管理器，请手动安装 curl 和 unzip${NC}"
    exit 1
  fi
}

##############################
# 写入 systemd 单元
##############################
write_systemd_service(){
  echo -e "${BLUE}>> 写入 systemd 单元：${SYSTEMD_SERVICE_FILE}${NC}"
  cat > "$SYSTEMD_SERVICE_FILE" <<EOF
[Unit]
Description=炸酱面探针 agent2
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
  --push-interval $PUSH_INTERVAL \\
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

##############################
# 写入 OpenRC 服务脚本
##############################
write_openrc_service(){
  echo -e "${BLUE}>> 写入 OpenRC 服务脚本：${OPENRC_SERVICE_FILE}${NC}"
  cat > "$OPENRC_SERVICE_FILE" <<'EOF'
#!/sbin/openrc-run
name="zjmagent2"
description="炸酱面探针 agent2"
command="{{AGENT_BIN}}"
command_args="--server-id {{SERVER_ID}} --token {{TOKEN}} --ws-url \"{{WS_URL}}\" --dashboard-url \"{{DASHBOARD_URL}}\" --interval {{INTERVAL}} --push-interval {{PUSH_INTERVAL}} --interface \"{{INTERFACE}}\""
directory="{{AGENT_DIR}}"
pidfile="/var/run/${RC_SVCNAME}.pid"
command_background=true
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
    -e "s|{{PUSH_INTERVAL}}|$PUSH_INTERVAL|g" \
    -e "s|{{INTERFACE}}|$INTERFACE|g" \
    -e "s|{{AGENT_DIR}}|$AGENT_DIR|g" \
    "$OPENRC_SERVICE_FILE"
  chmod +x "$OPENRC_SERVICE_FILE"
  rc-update add "$SERVICE_NAME" default
  rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
}

##############################
# 默认网卡检测
##############################
detect_default_iface(){
  # Linux: ip route
  if command -v ip >/dev/null 2>&1; then
    ip route 2>/dev/null | awk '/^default/ {print $5; exit}'
    return
  fi
  # macOS: route get default
  if [[ "$OS" == "Darwin" ]] && command -v route >/dev/null 2>&1; then
    route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'
    return
  fi
  # 其它：空
  echo ""
}

##############################
# 安装并启动 agent2
##############################
do_install(){
  echo -e "${BLUE}>>> 安装并启动 炸酱面探针 agent2 <<<${NC}"
  install_deps

  # 选择 ZIP 包
  ARCH="$(uname -m)"
  if grep -Eqi 'alpine' /etc/os-release 2>/dev/null || [[ -f /etc/alpine-release ]]; then
    ZIP_NAME="agent2-alpine.zip"
  elif ldd --version 2>&1 | grep -qi musl; then
    ZIP_NAME="agent2-alpine.zip"
  elif [[ "$ARCH" =~ ^(aarch64|arm64|armv8l)$ ]]; then
    ZIP_NAME="agent2-arm.zip"
  else
    ZIP_NAME="agent2.zip"
  fi
  AGENT_ZIP_URL="https://app.zjm.net/${ZIP_NAME}"
  echo -e "${BLUE}>> 检测到架构 ${ARCH}，下载：${ZIP_NAME}${NC}"

  # 清理旧目录
  if [[ -e "$AGENT_DIR" ]]; then
    echo -e "${YELLOW}⚠️ 删除旧目录：$AGENT_DIR${NC}"
    rm -rf "$AGENT_DIR"
  fi

  echo -e "${BLUE}>> 解压到 ${AGENT_DIR}${NC}"
  mkdir -p "$AGENT_DIR"
  tmpzip="/tmp/${ZIP_NAME}"
  curl -fL "$AGENT_ZIP_URL" -o "$tmpzip"
  # 安静解压；不再使用 -x 排除不存在的 agent.log，避免提示
  unzip -o -q "$tmpzip" -d "$AGENT_DIR"
  rm -f "$tmpzip"

  # 查找可执行
  if [ ! -f "$AGENT_BIN" ]; then
    FOUND_BIN=$(find "$AGENT_DIR" -maxdepth 2 -type f -name "agent" | head -n1 || true)
    if [[ -n "$FOUND_BIN" ]]; then
      AGENT_BIN="$FOUND_BIN"
      echo -e "${YELLOW}⚠️ 可执行改用：$AGENT_BIN${NC}"
    else
      echo -e "${YELLOW}❌ 找不到 agent 可执行，请检查压缩包内容${NC}"
      exit 1
    fi
  fi
  chmod +x "$AGENT_BIN"

  # CLI 模式或交互输入（不再询问本地采样 interval，默认 5）
  if [[ $CLI_MODE -eq 0 ]]; then
    read -r -p "请输入服务器唯一标识（server_id）： " SERVER_ID
    read -r -p "请输入令牌（token）： " TOKEN
    read -r -p "请输入 WebSocket 地址（ws-url）： " WS_URL
    read -r -p "请输入主控地址（dashboard-url）： " DASHBOARD_URL
    read -r -p "请输入推送间隔 push-interval（秒，默认 ${PUSH_INTERVAL}）： " tmp
    PUSH_INTERVAL="${tmp:-$PUSH_INTERVAL}"
  fi

  # 网卡接口：CLI 自动选；交互询问
  DEFAULT_IFACE="$(detect_default_iface)"
  if [[ $CLI_MODE -eq 1 ]]; then
    if [[ -n "$DEFAULT_IFACE" ]]; then
      INTERFACE="$DEFAULT_IFACE"
      echo -e "${BLUE}CLI 模式，自动使用接口：${INTERFACE}${NC}"
    else
      echo -e "${YELLOW}⚠️ CLI 模式下未检测到接口，请用 --interface 指定${NC}"
      exit 1
    fi
  else
    if [[ -n "$DEFAULT_IFACE" ]]; then
      echo -e "${BLUE}检测到默认接口：${DEFAULT_IFACE}${NC}"
      read -r -p "使用该接口？(Y/n) " yn
      if [[ "$yn" =~ ^[Nn]$ ]]; then
        read -r -p "请输入接口： " INTERFACE
      else
        INTERFACE="$DEFAULT_IFACE"
      fi
    else
      read -r -p "未检测到接口，请输入： " INTERFACE
    fi
  fi

  # 启动服务
  if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    write_systemd_service
    echo -e "${GREEN}✅ 使用 systemd，安装并启动完成${NC}"
  elif command -v rc-update >/dev/null 2>&1 && command -v openrc >/dev/null 2>&1; then
    write_openrc_service
    echo -e "${GREEN}✅ 使用 OpenRC，安装并启动完成${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC，手动后台运行：${NC}"
    echo -e "${YELLOW}  cd $AGENT_DIR && nohup $AGENT_BIN --server-id $SERVER_ID --token $TOKEN --ws-url \"$WS_URL\" --dashboard-url \"$DASHBOARD_URL\" --interval $INTERVAL --push-interval $PUSH_INTERVAL --interface \"$INTERFACE\" >/dev/null 2>&1 &${NC}"
    echo -e "${GREEN}✅ 二进制已就绪，请自行集成启动${NC}"
  fi
}

##############################
# 停止/重启/卸载
##############################
do_stop(){
  echo -e "${BLUE}>> 停止 ${SERVICE_NAME} 服务${NC}"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}.service" || true
    echo -e "${GREEN}✅ 服务已停止${NC}"
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" stop || true
    echo -e "${GREEN}✅ 服务已停止${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC，请手动停止${NC}"
  fi
}
do_restart(){
  echo -e "${BLUE}>> 重启 ${SERVICE_NAME} 服务${NC}"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "${SERVICE_NAME}.service"
    echo -e "${GREEN}✅ 服务已重启${NC}"
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
    echo -e "${GREEN}✅ 服务已重启${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC，请手动重启${NC}"
  fi
}
do_uninstall(){
  echo -e "${BLUE}>> 卸载 ${SERVICE_NAME} 服务${NC}"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${GREEN}✅ 服务已卸载${NC}"
  elif command -v rc-update >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    rc-update del "$SERVICE_NAME" default 2>/dev/null || true
    rm -f "$OPENRC_SERVICE_FILE"
    echo -e "${GREEN}✅ 服务已卸载${NC}"
  else
    echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC，请手动清理${NC}"
  fi
}

##############################
# 解析 CLI 参数
##############################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-id)     SERVER_ID="$2";     CLI_MODE=1; shift 2;;
    --token)         TOKEN="$2";         CLI_MODE=1; shift 2;;
    --ws-url)        WS_URL="$2";        CLI_MODE=1; shift 2;;
    --dashboard-url) DASHBOARD_URL="$2"; CLI_MODE=1; shift 2;;
    --interval)      INTERVAL="$2";      CLI_MODE=1; shift 2;;       # 允许覆盖，默认5
    --push-interval) PUSH_INTERVAL="$2"; CLI_MODE=1; shift 2;;
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

##############################
# 状态提示
##############################
echo
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    echo -e "${GREEN}${SERVICE_NAME} 服务状态（systemd）：运行中${NC}"
  else
    echo -e "${YELLOW}${SERVICE_NAME} 服务状态（systemd）：未运行${NC}"
  fi
elif command -v rc-service >/dev/null 2>&1; then
  if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
    echo -e "${GREEN}${SERVICE_NAME} 服务状态（OpenRC）：运行中${NC}"
  else
    echo -e "${YELLOW}${SERVICE_NAME} 服务状态（OpenRC）：未运行或未配置${NC}"
  fi
else
  echo -e "${YELLOW}⚠️ 未检测到 systemd/OpenRC 服务管理${NC}"
fi
echo

##############################
# 交互式菜单
##############################
echo -e "${BLUE}炸酱面探针 agent2${NC}"
echo "1) 安装并启动"
echo "2) 停止"
echo "3) 重启"
echo "4) 卸载"
echo "5) 退出"
read -r -p "输入 [1-5]: " opt
case "$opt" in
  1) do_install     ;;
  2) do_stop        ;;
  3) do_restart     ;;
  4) do_uninstall   ;;
  5) echo "退出"; exit 0 ;;
  *) echo "无效选项"; exit 1 ;;
esac
