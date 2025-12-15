#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent2.sh
# 交互式安装/管理 炸酱面探针 agent2 服务脚本（systemd / OpenRC / 其它）
# 下载地址：https://app.zjm.net/agent2.zip / agent2-alpine.zip / agent2-arm.zip
#
# ✅ 改进点：
# - 若已存在目录 zjmagent2 且存在 agent 可执行文件，则不重复下载，直接写服务并启动/重启
# - 依赖按需安装（curl/unzip 缺哪个装哪个）
# - 下载使用临时文件/临时目录并自动清理
# - uninstall 时删除服务文件 + 删除 zjmagent2 目录（含 agent 文件）
############################################

# 平台检测：允许 Linux / macOS / WSL / Git-Bash
OS="$(uname -s)"
if [[ ! "$OS" =~ ^(Linux|Darwin|MINGW|MSYS) ]]; then
  echo "⚠️ 当前系统 $OS 不支持本脚本，请在 Linux/macOS/WSL 或 Git Bash 下运行。"
  exit 1
fi

# 必须以 root 用户运行
if [[ "$(id -u)" -ne 0 ]]; then
  echo "⚠️ 请以 root 或 sudo 权限运行此脚本"
  exit 1
fi

# 颜色（按你的偏好：不使用红色）
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}>> $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️ $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }

# 服务名与路径
SERVICE_NAME="zjmagent2"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"

# 项目目录与 Agent 路径（保持与你原脚本一致：脚本所在目录）
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="${PROJECT_DIR}/${SERVICE_NAME}"
AGENT_BIN="${AGENT_DIR}/agent"

# CLI 模式标志及参数（默认：采样 5 秒、推送 30 秒）
CLI_MODE=0
SERVER_ID=""; TOKEN=""; WS_URL=""; DASHBOARD_URL=""
INTERVAL=5
PUSH_INTERVAL=30
INTERFACE=""

TMPDIR=""
cleanup() {
  [[ -n "${TMPDIR}" && -d "${TMPDIR}" ]] && rm -rf "${TMPDIR}" || true
}
trap cleanup EXIT

need_cmd() { command -v "$1" >/dev/null 2>&1; }

##############################################
# 安装依赖：curl unzip（按需）
##############################################
install_deps(){
  local missing=()
  need_cmd curl  || missing+=("curl")
  need_cmd unzip || missing+=("unzip")

  if (( ${#missing[@]} == 0 )); then
    log "依赖已满足：curl / unzip"
    return
  fi

  log "安装依赖：${missing[*]}"
  if need_cmd apt-get; then
    apt-get update -y
    apt-get install -y "${missing[@]}"
  elif need_cmd yum; then
    yum install -y "${missing[@]}"
  elif need_cmd dnf; then
    dnf install -y "${missing[@]}"
  elif need_cmd pacman; then
    pacman -Sy --noconfirm "${missing[@]}"
  elif need_cmd apk; then
    apk add --no-cache "${missing[@]}"
  elif need_cmd brew; then
    brew install "${missing[@]}"
  else
    warn "无法识别包管理器，请手动安装：${missing[*]}"
    exit 1
  fi
}

##############################################
# 默认网卡检测
##############################################
detect_default_iface(){
  # Linux: ip route
  if need_cmd ip; then
    ip route 2>/dev/null | awk '/^default/ {print $5; exit}'
    return
  fi
  # macOS: route get default
  if [[ "$OS" == "Darwin" ]] && need_cmd route; then
    route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'
    return
  fi
  echo ""
}

##############################################
# 选择 ZIP 包
##############################################
choose_zip(){
  local arch zip
  arch="$(uname -m)"

  # Alpine / musl 优先
  if grep -Eqi 'alpine' /etc/os-release 2>/dev/null || [[ -f /etc/alpine-release ]]; then
    zip="agent2-alpine.zip"
  elif need_cmd ldd && ldd --version 2>&1 | grep -qi musl; then
    zip="agent2-alpine.zip"
  elif [[ "$arch" =~ ^(aarch64|arm64|armv8l)$ ]]; then
    zip="agent2-arm.zip"
  else
    zip="agent2.zip"
  fi

  echo "$zip"
}

##############################################
# 下载并解压 agent2（仅在需要时调用）
##############################################
download_and_extract(){
  install_deps

  local zip_name url tmpzip
  zip_name="$(choose_zip)"
  url="https://app.zjm.net/${zip_name}"

  log "检测到架构 $(uname -m)，准备下载：${zip_name}"

  TMPDIR="$(mktemp -d)"
  tmpzip="${TMPDIR}/${zip_name}"

  # 清理旧目录（仅在需要重新下载时）
  if [[ -e "$AGENT_DIR" ]]; then
    warn "将覆盖旧目录：$AGENT_DIR"
    rm -rf "$AGENT_DIR"
  fi
  mkdir -p "$AGENT_DIR"

  log "下载：$url"
  curl -fL --retry 3 --retry-delay 1 --connect-timeout 10 "$url" -o "$tmpzip"

  log "解压到：$AGENT_DIR"
  unzip -o -q "$tmpzip" -d "$AGENT_DIR"

  # 兜底查找 agent
  if [[ ! -f "$AGENT_BIN" ]]; then
    local found
    found="$(find "$AGENT_DIR" -maxdepth 2 -type f -name "agent" | head -n1 || true)"
    if [[ -n "$found" ]]; then
      AGENT_BIN="$found"
      warn "可执行改用：$AGENT_BIN"
    else
      warn "找不到 agent 可执行，请检查压缩包内容"
      exit 1
    fi
  fi

  chmod +x "$AGENT_BIN"
  ok "二进制就绪：$AGENT_BIN"
}

##############################################
# 参数检查
##############################################
require_params(){
  if [[ -z "$SERVER_ID" || -z "$TOKEN" || -z "$WS_URL" || -z "$DASHBOARD_URL" ]]; then
    return 1
  fi
  return 0
}

##############################################
# 写入 systemd 单元
##############################################
write_systemd_service(){
  log "写入 systemd 单元：${SYSTEMD_SERVICE_FILE}"
  cat > "$SYSTEMD_SERVICE_FILE" <<EOF
[Unit]
Description=炸酱面探针 agent2
After=network.target

[Service]
Type=simple
WorkingDirectory=${AGENT_DIR}
ExecStart=${AGENT_BIN} --server-id ${SERVER_ID} --token ${TOKEN} --ws-url ${WS_URL} --dashboard-url ${DASHBOARD_URL} --interval ${INTERVAL} --push-interval ${PUSH_INTERVAL} --interface ${INTERFACE}
Restart=always
RestartSec=5
Environment=AGENT_LOG_LEVEL=INFO

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  systemctl restart "${SERVICE_NAME}.service"
}

##############################################
# 写入 OpenRC 服务脚本
##############################################
write_openrc_service(){
  log "写入 OpenRC 服务脚本：${OPENRC_SERVICE_FILE}"
  cat > "$OPENRC_SERVICE_FILE" <<EOF
#!/sbin/openrc-run
name="${SERVICE_NAME}"
description="炸酱面探针 agent2"
command="${AGENT_BIN}"
command_args="--server-id ${SERVER_ID} --token ${TOKEN} --ws-url ${WS_URL} --dashboard-url ${DASHBOARD_URL} --interval ${INTERVAL} --push-interval ${PUSH_INTERVAL} --interface ${INTERFACE}"
directory="${AGENT_DIR}"
pidfile="/var/run/\${RC_SVCNAME}.pid"
command_background=true

start_pre() {
  checkpath --directory --mode 0755 "${AGENT_DIR}"
}
EOF
  chmod +x "$OPENRC_SERVICE_FILE"
  rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
  rc-service "$SERVICE_NAME" restart >/dev/null 2>&1 || rc-service "$SERVICE_NAME" start
}

##############################################
# 安装并启动 agent2
##############################################
do_install(){
  log "安装并启动 炸酱面探针 agent2"

  # 1) 若目录与 agent 已存在，跳过下载
  if [[ -d "$AGENT_DIR" && -f "$AGENT_BIN" ]]; then
    chmod +x "$AGENT_BIN" || true
    ok "检测到已存在：$AGENT_BIN（跳过下载）"
  else
    download_and_extract
  fi

  # 2) 收集参数（CLI 或 交互）
  if [[ $CLI_MODE -eq 0 ]]; then
    read -r -p "请输入服务器唯一标识（server_id）： " SERVER_ID
    read -r -p "请输入令牌（token）： " TOKEN
    read -r -p "请输入 WebSocket 地址（ws-url）： " WS_URL
    read -r -p "请输入主控地址（dashboard-url）： " DASHBOARD_URL
    read -r -p "请输入推送间隔 push-interval（秒，默认 ${PUSH_INTERVAL}）： " tmp
    PUSH_INTERVAL="${tmp:-$PUSH_INTERVAL}"
  else
    # CLI 模式也允许只补缺的（更友好）
    if ! require_params; then
      warn "CLI 模式缺少必要参数（--server-id/--token/--ws-url/--dashboard-url），将进入交互补全"
      CLI_MODE=0
      do_install
      return
    fi
  fi

  # 3) 网卡接口
  if [[ -z "$INTERFACE" ]]; then
    local default_iface
    default_iface="$(detect_default_iface)"

    if [[ $CLI_MODE -eq 1 ]]; then
      if [[ -n "$default_iface" ]]; then
        INTERFACE="$default_iface"
        log "CLI 模式自动使用接口：${INTERFACE}"
      else
        warn "CLI 模式下未检测到接口，请用 --interface 指定"
        exit 1
      fi
    else
      if [[ -n "$default_iface" ]]; then
        log "检测到默认接口：${default_iface}"
        read -r -p "使用该接口？(Y/n) " yn
        if [[ "$yn" =~ ^[Nn]$ ]]; then
          read -r -p "请输入接口： " INTERFACE
        else
          INTERFACE="$default_iface"
        fi
      else
        read -r -p "未检测到接口，请输入： " INTERFACE
      fi
    fi
  fi

  # 4) 启动服务（写服务文件并重启）
  if need_cmd systemctl && systemctl --version >/dev/null 2>&1; then
    write_systemd_service
    ok "使用 systemd，安装/更新并启动完成"
  elif need_cmd rc-update && need_cmd openrc; then
    write_openrc_service
    ok "使用 OpenRC，安装/更新并启动完成"
  else
    warn "未检测到 systemd/OpenRC，手动后台运行："
    echo "  cd \"$AGENT_DIR\" && nohup \"$AGENT_BIN\" --server-id \"$SERVER_ID\" --token \"$TOKEN\" --ws-url \"$WS_URL\" --dashboard-url \"$DASHBOARD_URL\" --interval \"$INTERVAL\" --push-interval \"$PUSH_INTERVAL\" --interface \"$INTERFACE\" >/dev/null 2>&1 &"
    ok "二进制已就绪，请自行集成启动"
  fi
}

##############################################
# 停止/重启/卸载
##############################################
do_stop(){
  log "停止 ${SERVICE_NAME} 服务"
  if need_cmd systemctl; then
    systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
    ok "服务已停止"
  elif need_cmd rc-service; then
    rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
    ok "服务已停止"
  else
    warn "未检测到 systemd/OpenRC，请手动停止"
  fi
}

do_restart(){
  log "重启 ${SERVICE_NAME} 服务"
  if need_cmd systemctl; then
    systemctl restart "${SERVICE_NAME}.service"
    ok "服务已重启"
  elif need_cmd rc-service; then
    rc-service "$SERVICE_NAME" restart >/dev/null 2>&1 || rc-service "$SERVICE_NAME" start
    ok "服务已重启"
  else
    warn "未检测到 systemd/OpenRC，请手动重启"
  fi
}

do_uninstall(){
  log "卸载 ${SERVICE_NAME} 服务（并删除本地文件）"

  if need_cmd systemctl; then
    systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
    systemctl disable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload
    ok "systemd 服务已移除"
  elif need_cmd rc-update; then
    rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
    rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
    rm -f "$OPENRC_SERVICE_FILE"
    ok "OpenRC 服务已移除"
  else
    warn "未检测到 systemd/OpenRC，跳过服务卸载（仅清理文件）"
  fi

  if [[ -d "$AGENT_DIR" ]]; then
    rm -rf "$AGENT_DIR"
    ok "已删除目录：$AGENT_DIR"
  else
    log "目录不存在，无需删除：$AGENT_DIR"
  fi
}

##############################################
# 解析 CLI 参数
##############################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-id)     SERVER_ID="$2";     CLI_MODE=1; shift 2;;
    --token)         TOKEN="$2";         CLI_MODE=1; shift 2;;
    --ws-url)        WS_URL="$2";        CLI_MODE=1; shift 2;;
    --dashboard-url) DASHBOARD_URL="$2"; CLI_MODE=1; shift 2;;
    --interval)      INTERVAL="$2";      CLI_MODE=1; shift 2;;
    --push-interval) PUSH_INTERVAL="$2"; CLI_MODE=1; shift 2;;
    --interface)     INTERFACE="$2";     CLI_MODE=1; shift 2;;
    stop)            do_stop;            exit 0;;
    restart)         do_restart;         exit 0;;
    uninstall)       do_uninstall;       exit 0;;
    *) break;;
  esac
done

# 如果 CLI 模式且参数齐全，直接安装
if [[ $CLI_MODE -eq 1 ]] && require_params; then
  do_install
  exit 0
fi

##############################################
# 状态提示
##############################################
echo
if need_cmd systemctl; then
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    ok "${SERVICE_NAME} 服务状态（systemd）：运行中"
  else
    warn "${SERVICE_NAME} 服务状态（systemd）：未运行"
  fi
elif need_cmd rc-service; then
  if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
    ok "${SERVICE_NAME} 服务状态（OpenRC）：运行中"
  else
    warn "${SERVICE_NAME} 服务状态（OpenRC）：未运行或未配置"
  fi
else
  warn "未检测到 systemd/OpenRC 服务管理"
fi
echo

##############################################
# 交互式菜单
##############################################
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
