#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent2.sh
# 交互式安装/管理 炸酱面探针 agent2 服务脚本（systemd / OpenRC / 其它）
# 下载地址：https://app.zjm.net/agent2.zip / agent2-alpine.zip / agent2-arm.zip
#
# ✅ 关键改进（本版）：
# - CLI 模式不传 --interface 也会自动探测默认网卡（失败则兜底选第一个非 lo）
# - 修复“命令安装不成功、菜单成功”的常见原因：脚本在 curl|bash / bash -s 场景下 PROJECT_DIR 错误
# - 写入 systemd/openrc 时，只有在 INTERFACE 非空才写 --interface，避免空参数导致 agent 退出
# - 依赖按需安装（curl/unzip/ip），并兼容多发行版
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

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# 服务名与路径
SERVICE_NAME="zjmagent2"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"

# 解析脚本目录（✅ 兼容 curl|bash / bash -s / stdin 场景）
# - 若脚本真实路径不可用，则使用当前工作目录作为 PROJECT_DIR
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
if [[ -z "${SCRIPT_PATH}" || "${SCRIPT_PATH}" == "bash" || "${SCRIPT_PATH}" == "-bash" || "${SCRIPT_PATH}" == "sh" || "${SCRIPT_PATH}" == "-sh" || ! -f "${SCRIPT_PATH}" ]]; then
  PROJECT_DIR="$(pwd)"
else
  PROJECT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
fi

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

##############################################
# 安装依赖：curl unzip ip（按需）
##############################################
install_deps(){
  local missing=()
  need_cmd curl  || missing+=("curl")
  need_cmd unzip || missing+=("unzip")

  # 默认网卡探测更稳：尽量有 ip 命令
  if ! need_cmd ip; then
    missing+=("__NEED_IP__")
  fi

  if (( ${#missing[@]} == 0 )); then
    log "依赖已满足：curl / unzip / ip"
    return
  fi

  log "安装依赖：${missing[*]}"

  if need_cmd apt-get; then
    apt-get update -y
    local pkgs=()
    for m in "${missing[@]}"; do
      [[ "$m" == "__NEED_IP__" ]] && pkgs+=("iproute2") || pkgs+=("$m")
    done
    apt-get install -y "${pkgs[@]}"

  elif need_cmd apk; then
    local pkgs=()
    for m in "${missing[@]}"; do
      [[ "$m" == "__NEED_IP__" ]] && pkgs+=("iproute2") || pkgs+=("$m")
    done
    apk add --no-cache "${pkgs[@]}"

  elif need_cmd yum; then
    local pkgs=()
    for m in "${missing[@]}"; do
      [[ "$m" == "__NEED_IP__" ]] && pkgs+=("iproute") || pkgs+=("$m")
    done
    yum install -y "${pkgs[@]}"

  elif need_cmd dnf; then
    local pkgs=()
    for m in "${missing[@]}"; do
      [[ "$m" == "__NEED_IP__" ]] && pkgs+=("iproute") || pkgs+=("$m")
    done
    dnf install -y "${pkgs[@]}"

  elif need_cmd pacman; then
    local pkgs=()
    for m in "${missing[@]}"; do
      [[ "$m" == "__NEED_IP__" ]] && pkgs+=("iproute2") || pkgs+=("$m")
    done
    pacman -Sy --noconfirm "${pkgs[@]}"

  elif need_cmd brew; then
    local pkgs=()
    for m in "${missing[@]}"; do
      [[ "$m" == "__NEED_IP__" ]] && pkgs+=("iproute2mac") || pkgs+=("$m")
    done
    brew install "${pkgs[@]}"

  else
    warn "无法识别包管理器，请手动安装：curl unzip ip(或 iproute2/iproute)"
    exit 1
  fi
}

##############################################
# 默认网卡检测（✅ 多策略兜底）
##############################################
detect_default_iface(){
  # 1) 优先：默认路由
  if need_cmd ip; then
    local iface=""
    iface="$(ip -o -4 route show to default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [[ -n "$iface" ]] && { echo "$iface"; return; }

    # 2) 再试：对外路由探测
    iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [[ -n "$iface" ]] && { echo "$iface"; return; }
  fi

  # 3) /proc/net/route 兜底
  if [[ -r /proc/net/route ]]; then
    local iface=""
    iface="$(awk '$2=="00000000" && $1!="lo" {print $1; exit}' /proc/net/route 2>/dev/null || true)"
    [[ -n "$iface" ]] && { echo "$iface"; return; }
  fi

  # 4) 最后兜底：第一个非 lo 网卡
  if need_cmd ip; then
    ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}'
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
  log "安装目录：${AGENT_DIR}"

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
    found="$(find "$AGENT_DIR" -maxdepth 3 -type f -name "agent" | head -n1 || true)"
    if [[ -n "$found" ]]; then
      # 统一放到 AGENT_DIR/agent 位置，避免路径漂移
      mv -f "$found" "$AGENT_BIN" 2>/dev/null || true
      chmod +x "$AGENT_BIN" || true
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
  [[ -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]
}

##############################################
# 写入 systemd 单元（✅ 仅 INTERFACE 非空才写 --interface）
##############################################
write_systemd_service(){
  log "写入 systemd 单元：${SYSTEMD_SERVICE_FILE}"

  local iface_arg=""
  [[ -n "${INTERFACE}" ]] && iface_arg="--interface ${INTERFACE}"

  cat > "$SYSTEMD_SERVICE_FILE" <<EOF
[Unit]
Description=炸酱面探针 agent2
After=network.target

[Service]
Type=simple
WorkingDirectory=${AGENT_DIR}
ExecStart=${AGENT_BIN} --server-id ${SERVER_ID} --token ${TOKEN} --ws-url ${WS_URL} --dashboard-url ${DASHBOARD_URL} --interval ${INTERVAL} --push-interval ${PUSH_INTERVAL} ${iface_arg}
Restart=always
RestartSec=5
Environment=AGENT_LOG_LEVEL=INFO

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  if ! systemctl restart "${SERVICE_NAME}.service"; then
    warn "systemd 启动失败：请执行查看原因："
    echo "  systemctl status ${SERVICE_NAME}.service --no-pager"
    echo "  journalctl -xeu ${SERVICE_NAME}.service --no-pager | tail -n 200"
    exit 1
  fi
}

##############################################
# 写入 OpenRC 服务脚本（✅ 仅 INTERFACE 非空才写 --interface）
##############################################
write_openrc_service(){
  log "写入 OpenRC 服务脚本：${OPENRC_SERVICE_FILE}"

  local iface_arg=""
  [[ -n "${INTERFACE}" ]] && iface_arg="--interface ${INTERFACE}"

  cat > "$OPENRC_SERVICE_FILE" <<EOF
#!/sbin/openrc-run
name="${SERVICE_NAME}"
description="炸酱面探针 agent2"
command="${AGENT_BIN}"
command_args="--server-id ${SERVER_ID} --token ${TOKEN} --ws-url ${WS_URL} --dashboard-url ${DASHBOARD_URL} --interval ${INTERVAL} --push-interval ${PUSH_INTERVAL} ${iface_arg}"
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
  log "工作目录：${PROJECT_DIR}"

  # 0) 确保基础依赖（尤其 ip），避免 CLI 自动网卡探测失败
  install_deps

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
    read -r -p "请输入采样间隔 interval（秒，默认 ${INTERVAL}）： " tmpi
    INTERVAL="${tmpi:-$INTERVAL}"
    read -r -p "请输入推送间隔 push-interval（秒，默认 ${PUSH_INTERVAL}）： " tmpp
    PUSH_INTERVAL="${tmpp:-$PUSH_INTERVAL}"
  else
    # CLI 模式：缺啥就提示并退出（不做递归，避免逻辑绕）
    if ! require_params; then
      warn "CLI 模式缺少必要参数：--server-id/--token/--ws-url/--dashboard-url"
      echo "示例："
      echo "  bash install_zjmagent2.sh --server-id \"xxx\" --token \"xxx\" --ws-url \"http://1.2.3.4:9009\" --dashboard-url \"http://1.2.3.4:9009\" --interval 5 --push-interval 30"
      exit 1
    fi
  fi

  # 3) 网卡接口（✅ CLI 也自动用默认网卡；失败兜底非 lo）
  if [[ -z "${INTERFACE}" ]]; then
    local default_iface
    default_iface="$(detect_default_iface)"

    if [[ -n "$default_iface" ]]; then
      INTERFACE="$default_iface"
      log "自动使用默认接口：${INTERFACE}"
    else
      warn "未能探测到默认接口，将尝试选择第一个非 lo 网卡"
      if need_cmd ip; then
        INTERFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}')"
      fi
      [[ -n "${INTERFACE}" ]] || { warn "仍无法确定网卡接口，请手动传入 --interface"; exit 1; }
      log "兜底使用接口：${INTERFACE}"
    fi
  else
    log "使用用户指定接口：${INTERFACE}"
  fi

  # 4) 启动服务（写服务文件并重启）
  if need_cmd systemctl && systemctl --version >/dev/null 2>&1; then
    write_systemd_service
    ok "使用 systemd，安装/更新并启动完成"
  elif need_cmd rc-update && need_cmd openrc; then
    write_openrc_service
    ok "使用 OpenRC，安装/更新并启动完成"
  else
    warn "未检测到 systemd/OpenRC，将输出手动后台运行命令："
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
    --server-id)     SERVER_ID="${2:-}";     CLI_MODE=1; shift 2;;
    --token)         TOKEN="${2:-}";         CLI_MODE=1; shift 2;;
    --ws-url)        WS_URL="${2:-}";        CLI_MODE=1; shift 2;;
    --dashboard-url) DASHBOARD_URL="${2:-}"; CLI_MODE=1; shift 2;;
    --interval)      INTERVAL="${2:-5}";     CLI_MODE=1; shift 2;;
    --push-interval) PUSH_INTERVAL="${2:-30}"; CLI_MODE=1; shift 2;;
    --interface)     INTERFACE="${2:-}";     CLI_MODE=1; shift 2;;

    install)         CLI_MODE=1; do_install; exit 0;;
    stop)            do_stop;    exit 0;;
    restart)         do_restart; exit 0;;
    uninstall)       do_uninstall; exit 0;;
    *) break;;
  esac
done

# 如果 CLI 模式且参数齐全，直接安装（✅ 不需要 --interface）
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
