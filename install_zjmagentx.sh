#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# install_zjmagent.sh · 最终版
# - 自动选取 zip，根据系统/架构下载
# - 解压后自动识别可执行
# - 支持交互/非交互安装；CLI 模式下直接用默认网卡
# - OpenRC 下用 openrc-run background，不再用 start-stop-daemon
# - 安装前清理旧服务脚本
############################################

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

SERVICE_NAME="zjmagent"
SERVICE_FILE_SYSTEMD="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_FILE_OPENRC="/etc/init.d/${SERVICE_NAME}"

BASE_AGENT_URL="${BASE_AGENT_URL:-https://app.zjm.net}"
FILE_AMD="agent.zip"
FILE_ARM="agent-arm.zip"
FILE_ALPINE_AMD="agent-alpine.zip"
FILE_ALPINE_ARM="agent-alpinearm.zip"

ALPINE_GLIBC_VER="2.35-r1"
ALPINE_GLIBC_BASE_URL="https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${ALPINE_GLIBC_VER}"

CLI_MODE=0
SERVER_ID="${SERVER_ID:-}"
TOKEN="${TOKEN:-}"
WS_URL="${WS_URL:-}"
DASHBOARD_URL="${DASHBOARD_URL:-}"
INTERVAL="${INTERVAL:-1}"
INTERFACE="${INTERFACE:-}"
INIT_SYS="unknown"

TMP_DIR=""
cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

print_usage() {
  cat <<EOF
用法: $0 [OPTIONS] [stop|restart|uninstall]

Options:
  --server-id ID        非交互安装时必须
  --token TOKEN         非交互安装时必须
  --ws-url URL          非交互安装时必须
  --dashboard-url URL   非交互安装时必须
  --interval 秒         采集间隔，正整数
  --interface IFACE     网卡名称（CLI 模式下可指定；否则自动取默认）
  -h, --help            显示帮助

示例:
  sudo $0
  sudo SERVER_ID=xxx TOKEN=yyy WS_URL=wss://... DASHBOARD_URL=https://... INTERFACE=eth0 INTERVAL=5 $0
  sudo $0 --server-id xxx --token yyy --ws-url wss://... --dashboard-url https://... --interface eth0 --interval 5
  sudo $0 stop
  sudo $0 restart
  sudo $0 uninstall
EOF
}

if [[ $EUID -ne 0 ]]; then
  echo -e "${YELLOW}⚠️ 请使用 root / sudo 运行脚本${NC}"
  exit 1
fi

detect_init_system() {
  if command -v systemctl &>/dev/null && systemctl --version &>/dev/null; then
    INIT_SYS="systemd"
  elif command -v rc-service &>/dev/null; then
    INIT_SYS="openrc"
  else
    INIT_SYS="none"
  fi
}

require_cmd() {
  local cmd="$1" pkg_hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    if [[ -n "$pkg_hint" ]]; then
      echo -e "${YELLOW}⚠️ 未检测到命令 '$cmd'，请安装${pkg_hint}${NC}"
    else
      echo -e "${YELLOW}⚠️ 未检测到命令 '$cmd'，请安装${NC}"
    fi
    return 1
  fi
  return 0
}

install_deps() {
  echo -e "${BLUE}>> 检测并安装依赖${NC}"
  if command -v apt-get &>/dev/null; then
    apt-get update -qq
    apt-get install -y --no-install-recommends curl unzip iproute2 || \
      echo -e "${YELLOW}安装 curl/unzip/iproute2 失败，请手动安装${NC}"
  elif command -v dnf &>/dev/null; then
    dnf install -y curl unzip iproute || \
      echo -e "${YELLOW}安装 curl/unzip/iproute 失败，请手动安装${NC}"
  elif command -v yum &>/dev/null; then
    yum install -y curl unzip iproute || \
      echo -e "${YELLOW}安装 curl/unzip/iproute 失败，请手动安装${NC}"
  elif command -v pacman &>/dev/null; then
    pacman -Sy --noconfirm curl unzip iproute2 || \
      echo -e "${YELLOW}安装 curl/unzip/iproute2 失败，请手动安装${NC}"
  elif command -v apk &>/dev/null; then
    echo -e "${BLUE}>> Alpine: 启用 community 源、更新索引、安装 curl unzip iproute2 libc6-compat${NC}"
    if ! grep -E '^[^#].*community' /etc/apk/repositories &>/dev/null; then
      sed -i 's@^#\s*\(http.*community\)@\1@' /etc/apk/repositories || true
    fi
    apk update
    apk add --no-cache curl unzip iproute2 libc6-compat || \
      echo -e "${YELLOW}安装 curl/unzip/iproute2/libc6-compat 失败，请手动安装${NC}"
    if [[ ! -f "/usr/glibc-compat/lib/ld-linux-x86-64.so.2" ]]; then
      echo -e "${BLUE}>> Alpine: 安装 glibc 兼容层${NC}"
      if ! command -v wget &>/dev/null; then
        apk add --no-cache wget || {
          echo -e "${YELLOW}⚠️ wget 安装失败，请手动安装 glibc 兼容层${NC}"
          return
        }
      fi
      TMP_DIR="$(mktemp -d)"
      local ver="$ALPINE_GLIBC_VER"
      local base="$ALPINE_GLIBC_BASE_URL"
      wget -q -O "${TMP_DIR}/glibc.apk" "${base}/glibc-${ver}.apk" || {
        echo -e "${YELLOW}⚠️ 下载 glibc-${ver}.apk 失败${NC}"
        return
      }
      wget -q -O "${TMP_DIR}/glibc-bin.apk" "${base}/glibc-bin-${ver}.apk" || {
        echo -e "${YELLOW}⚠️ 下载 glibc-bin-${ver}.apk 失败${NC}"
        return
      }
      apk add --no-cache --allow-untrusted "${TMP_DIR}/glibc.apk" "${TMP_DIR}/glibc-bin.apk" || {
        echo -e "${YELLOW}⚠️ 安装 glibc 兼容层失败${NC}"
      }
    else
      echo -e "${BLUE}>> Alpine: 已检测到 glibc-compat，跳过安装${NC}"
    fi
  else
    echo -e "${YELLOW}无法识别包管理器，请手动安装 curl / unzip / iproute2${NC}"
  fi
  for cmd in curl unzip ip; do
    require_cmd "$cmd" || true
  done
}

is_alpine() {
  if [[ -f /etc/os-release ]] && grep -qi '^ID=.*alpine' /etc/os-release; then
    return 0
  elif command -v apk &>/dev/null; then
    return 0
  fi
  return 1
}

get_arch_type() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo "amd";;
    aarch64|arm64) echo "arm";;
    armv7l|armv6l) echo "arm";;
    *) echo "unknown";;
  esac
}

select_agent_url() {
  if [[ -n "${AGENT_ZIP_URL_OVERRIDE:-}" ]]; then
    AGENT_ZIP_URL="$AGENT_ZIP_URL_OVERRIDE"
    echo -e "${BLUE}>> 使用用户指定下载 URL: $AGENT_ZIP_URL${NC}"
    return
  fi
  local arch
  arch="$(get_arch_type)"
  local file
  if is_alpine; then
    case "$arch" in
      amd) file="$FILE_ALPINE_AMD";;
      arm) file="$FILE_ALPINE_ARM";;
      *)
        echo -e "${YELLOW}⚠️ 无法识别架构 '$arch'，默认使用 Alpine AMD 包${NC}"
        file="$FILE_ALPINE_AMD";;
    esac
  else
    case "$arch" in
      amd) file="$FILE_AMD";;
      arm) file="$FILE_ARM";;
      *)
        echo -e "${YELLOW}⚠️ 无法识别架构 '$arch'，默认使用通用 AMD 包${NC}"
        file="$FILE_AMD";;
    esac
  fi
  AGENT_ZIP_URL="${BASE_AGENT_URL%/}/${file}"
  echo -e "${BLUE}>> 选择下载包: $file${NC}"
}

create_systemd_unit() {
  mkdir -p /var/log
  if [[ -z "$SERVER_ID" || -z "$TOKEN" || -z "$WS_URL" || -z "$DASHBOARD_URL" ]]; then
    echo -e "${YELLOW}❌ 创建 systemd 单元前，必要参数不能为空${NC}"
    exit 1
  fi
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
  # 清理旧服务脚本，避免残留
  if rc-update show | grep -qw "$SERVICE_NAME"; then
    rc-update del "$SERVICE_NAME" default || true
  fi
  if [[ -f "$SERVICE_FILE_OPENRC" ]]; then
    rm -f "$SERVICE_FILE_OPENRC"
  fi

  local loader_path="/usr/glibc-compat/lib/ld-linux-x86-64.so.2"
  if [[ ! -f "$loader_path" ]]; then
    echo -e "${YELLOW}⚠️ 未检测到 glibc loader ($loader_path)，请确认 glibc 兼容层已安装${NC}"
  fi
  if [[ -z "$SERVER_ID" || -z "$TOKEN" || -z "$WS_URL" || -z "$DASHBOARD_URL" ]]; then
    echo -e "${YELLOW}❌ 创建 OpenRC 脚本前，必要参数不能为空${NC}"
    exit 1
  fi

  cat >"$SERVICE_FILE_OPENRC" <<EOF
#!/sbin/openrc-run
description="炸酱面探针Agent"
depend() {
    need net
}

# pidfile 路径
pidfile="/run/${SERVICE_NAME}.pid"
command="$AGENT_BIN"
command_args="--server-id $SERVER_ID --token $TOKEN --ws-url $WS_URL --dashboard-url $DASHBOARD_URL --interval $INTERVAL --interface $INTERFACE"
command_background=true
output_log="/var/log/${SERVICE_NAME}.log"
error_log="/var/log/${SERVICE_NAME}.err"
EOF

  chmod +x "$SERVICE_FILE_OPENRC"
  rc-update add "$SERVICE_NAME" default
  if ! rc-service "$SERVICE_NAME" restart; then
    rc-service "$SERVICE_NAME" start || {
      echo -e "${YELLOW}⚠️ 无法启动 OpenRC 服务，请手动检查日志${NC}"
    }
  fi
}

do_install() {
  echo -e "${BLUE}>>> 安装并启动 炸酱面探针Agent${NC}"
  detect_init_system
  install_deps

  select_agent_url

  echo -e "${BLUE}>> 下载并解压 $AGENT_ZIP_URL → 临时目录${NC}"
  TMP_DIR="$(mktemp -d)"
  local zipfile="${TMP_DIR}/agent.zip"
  if command -v curl &>/dev/null; then
    if ! curl -fSL "$AGENT_ZIP_URL" -o "$zipfile"; then
      echo -e "${YELLOW}❌ 下载 $AGENT_ZIP_URL 失败，请检查 URL 或网络${NC}"
      exit 1
    fi
  elif command -v wget &>/dev/null; then
    if ! wget -qO "$zipfile" "$AGENT_ZIP_URL"; then
      echo -e "${YELLOW}❌ 下载 $AGENT_ZIP_URL 失败，请检查 URL 或网络${NC}"
      exit 1
    fi
  else
    echo -e "${YELLOW}❌ 未安装 curl 或 wget，无法下载 agent.zip${NC}"
    exit 1
  fi

  AGENT_DIR="$(cd "$(dirname "$0")" && pwd)/agent"
  rm -rf "$AGENT_DIR"
  mkdir -p "$AGENT_DIR"
  if ! unzip -qo "$zipfile" -d "$AGENT_DIR"; then
    echo -e "${YELLOW}❌ 解压 $zipfile 失败，请检查 zip 包内容${NC}"
    exit 1
  fi

  echo -e "${BLUE}>> 识别可执行文件...${NC}"
  mapfile -t execs < <(find "$AGENT_DIR" -type f -perm /u=x,g=x,o=x 2>/dev/null)
  if [[ ${#execs[@]} -eq 0 ]]; then
    echo -e "${YELLOW}❌ 未在解压后的目录中发现任何可执行文件，请确认 ZIP 包结构${NC}"
    echo -e "${BLUE}解压后文件列表:${NC}"
    find "$AGENT_DIR" -maxdepth 2 | sed 's/^/  /'
    exit 1
  fi
  AGENT_BIN_CANDIDATE=""
  for f in "${execs[@]}"; do
    base="$(basename "$f")"
    if [[ "$base" == "agent" || "$base" == "zjmagent" ]]; then
      AGENT_BIN_CANDIDATE="$f"
      break
    fi
  done
  if [[ -z "$AGENT_BIN_CANDIDATE" ]]; then
    AGENT_BIN_CANDIDATE="${execs[0]}"
    echo -e "${YELLOW}⚠️ 未找到名为 agent 的可执行，使用第一个可执行: $(basename "$AGENT_BIN_CANDIDATE")${NC}"
  fi
  AGENT_BIN="$AGENT_BIN_CANDIDATE"
  chmod +x "$AGENT_BIN"
  echo -e "${GREEN}>> 选定可执行文件: $AGENT_BIN${NC}"

  if [[ $CLI_MODE -eq 0 ]]; then
    echo -e "${BLUE}>>> 请输入以下配置（回车跳过使用已有/默认）${NC}"
    read -r -p "服务器唯一标识（server_id）: " tmp && SERVER_ID="${tmp:-$SERVER_ID}"
    read -r -p "令牌（token）: " tmp && TOKEN="${tmp:-$TOKEN}"
    read -r -p "WebSocket 地址（ws-url）: " tmp && WS_URL="${tmp:-$WS_URL}"
    read -r -p "主控地址（dashboard-url）: " tmp && DASHBOARD_URL="${tmp:-$DASHBOARD_URL}"
    read -r -p "采集间隔(秒，默认 $INTERVAL): " tmp && {
      if [[ "$tmp" =~ ^[1-9][0-9]*$ ]]; then
        INTERVAL="$tmp"
      else
        echo -e "${YELLOW}无效间隔，使用默认 $INTERVAL 秒${NC}"
      fi
    }
  else
    echo -e "${BLUE}>>> 使用 CLI/环境变量 提供的参数进行安装，无交互${NC}"
  fi

  for var in SERVER_ID TOKEN WS_URL DASHBOARD_URL; do
    if [[ -z "${!var}" ]]; then
      echo -e "${YELLOW}❌ 参数 $var 不能为空，请检查后重试${NC}"
      exit 1
    fi
  done

  # CLI 模式下使用默认网卡
  local DEFAULT_IFACE
  DEFAULT_IFACE="$(ip route 2>/dev/null | awk '/^default/{print $5;exit}')"
  [[ -z "$DEFAULT_IFACE" ]] && DEFAULT_IFACE="eth0"
  if [[ $CLI_MODE -eq 1 ]]; then
    INTERFACE="${INTERFACE:-$DEFAULT_IFACE}"
    if ! ip link show "$INTERFACE" &>/dev/null; then
      echo -e "${YELLOW}⚠️ 默认网卡 $INTERFACE 不存在或不可用，可能无法正常采集流量${NC}"
    fi
    echo -e "${BLUE}>> 使用默认网卡：$INTERFACE${NC}"
  else
    echo -e "${BLUE}检测到默认网卡：$DEFAULT_IFACE${NC}"
    read -r -p "是否使用该网卡？(Y/n) " yn
    if [[ "${yn:-Y}" =~ ^[Nn]$ ]]; then
      read -r -p "请输入网卡名: " tmp
      if ip link show "$tmp" &>/dev/null; then
        INTERFACE="$tmp"
      else
        echo -e "${YELLOW}⚠️ 网卡 $tmp 不存在，使用默认 $DEFAULT_IFACE${NC}"
        INTERFACE="$DEFAULT_IFACE"
      fi
    else
      INTERFACE="$DEFAULT_IFACE"
    fi
  fi

  detect_init_system
  case "$INIT_SYS" in
    systemd)
      create_systemd_unit
      ;;
    openrc)
      create_openrc_script
      ;;
    none)
      echo -e "${YELLOW}⚠️ 未检测到 systemd/openrc，跳过服务安装${NC}"
      echo "可手动运行：$AGENT_BIN --server-id $SERVER_ID --token $TOKEN --ws-url $WS_URL --dashboard-url $DASHBOARD_URL --interval $INTERVAL --interface $INTERFACE"
      ;;
  esac

  echo -e "${GREEN}✅ Agent 安装完成（Init=$INIT_SYS）${NC}"
}

do_stop() {
  detect_init_system
  if [[ $INIT_SYS == systemd ]]; then
    systemctl stop "$SERVICE_NAME" && echo -e "${GREEN}服务已停止${NC}" || echo -e "${YELLOW}停止服务失败或服务未运行${NC}"
  elif [[ $INIT_SYS == openrc ]]; then
    rc-service "$SERVICE_NAME" stop && echo -e "${GREEN}服务已停止${NC}" || echo -e "${YELLOW}停止服务失败或服务未运行${NC}"
  else
    echo -e "${YELLOW}未检测到已安装服务${NC}"
  fi
}

do_restart() {
  detect_init_system
  if [[ $INIT_SYS == systemd ]]; then
    systemctl restart "$SERVICE_NAME" && echo -e "${GREEN}服务已重启${NC}" || echo -e "${YELLOW}重启服务失败${NC}"
  elif [[ $INIT_SYS == openrc ]]; then
    rc-service "$SERVICE_NAME" restart && echo -e "${GREEN}服务已重启${NC}" || echo -e "${YELLOW}重启服务失败${NC}"
  else
    echo -e "${YELLOW}未检测到已安装服务${NC}"
  fi
}

do_uninstall() {
  detect_init_system
  if [[ $INIT_SYS == systemd ]]; then
    systemctl disable --now "$SERVICE_NAME" &>/dev/null || true
    rm -f "$SERVICE_FILE_SYSTEMD"
    systemctl daemon-reload
    echo -e "${GREEN}✅ Systemd 服务已卸载${NC}"
  elif [[ $INIT_SYS == openrc ]]; then
    rc-service "$SERVICE_NAME" stop &>/dev/null || true
    rc-update del "$SERVICE_NAME" default &>/dev/null || true
    rm -f "$SERVICE_FILE_OPENRC"
    echo -e "${GREEN}✅ OpenRC 服务已卸载${NC}"
  else
    echo -e "${YELLOW}未检测到 systemd/openrc 服务，无需卸载${NC}"
  fi
}

# 解析 CLI 参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-id)
      SERVER_ID="$2"; CLI_MODE=1; shift 2;;
    --token)
      TOKEN="$2"; CLI_MODE=1; shift 2;;
    --ws-url)
      WS_URL="$2"; CLI_MODE=1; shift 2;;
    --dashboard-url)
      DASHBOARD_URL="$2"; CLI_MODE=1; shift 2;;
    --interval)
      if [[ "$2" =~ ^[1-9][0-9]*$ ]]; then INTERVAL="$2"; else echo -e "${YELLOW}⚠️ 无效 interval: $2${NC}"; fi
      CLI_MODE=1; shift 2;;
    --interface)
      INTERFACE="$2"; CLI_MODE=1; shift 2;;
    -h|--help)
      print_usage; exit 0;;
    stop)
      do_stop; exit 0;;
    restart)
      do_restart; exit 0;;
    uninstall)
      do_uninstall; exit 0;;
    *)
      echo -e "${YELLOW}未知选项: $1${NC}"; print_usage; exit 1;;
  esac
done

if [[ $CLI_MODE -eq 0 && -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]; then
  CLI_MODE=1
fi

if [[ $CLI_MODE -eq 1 && -n "$SERVER_ID" && -n "$TOKEN" && -n "$WS_URL" && -n "$DASHBOARD_URL" ]]; then
  do_install
  exit 0
fi

# 交互菜单
detect_init_system
echo
if [[ $INIT_SYS == systemd ]]; then
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}${SERVICE_NAME} 服务状态：运行中${NC}"
  else
    echo -e "${YELLOW}${SERVICE_NAME} 服务状态：未运行${NC}"
  fi
elif [[ $INIT_SYS == openrc ]]; then
  if rc-service "$SERVICE_NAME" status &>/dev/null; then
    echo -e "${GREEN}${SERVICE_NAME} 服务状态：运行中${NC}"
  else
    echo -e "${YELLOW}${SERVICE_NAME} 服务状态：未运行${NC}"
  fi
else
  echo -e "${YELLOW}未检测到系统服务（systemd/openrc）${NC}"
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
  *) echo -e "${YELLOW}无效选项${NC}"; exit 1 ;;
esac
