#!/usr/bin/env bash
# ============================================================
# Fedora 44 最小安装 — Niri/Noctalia v5 前置配置脚本 (AMD 版) v10
# 使用方法: sudo bash setup-niri-pre-v10.sh
#
# 【本版范围】一路配到「重启即可进图形登录界面，且首次登录就能用」。
#   含: greetd 会话配置、kitty 终端 + 美化配置、最小 niri 配置(自启 Noctalia)
#   最小安装无旧显示管理器，故官方文档 §4「Replace the current display manager
#   safely」不适用，本脚本不含该步。
#
# 官方文档来源 (2026-09-17 拉取):
#     - 包安装: https://docs.noctalia.dev/noctalia/getting-started/installation/
#     - Greeter: https://docs.noctalia.dev/greeter/installation/
#
# 【v4→v8 关键更正】
#   1. noctalia v5 shell 在 == Fedora 44+ 默认仓库 ==，不是 Terra。
#      文档原文: "Noctalia is available from the default repos for Fedora 44 and up."
#      (Terra 里也有 noctalia，实测版本 5.0.0~beta.9；Terra 的 noctalia-legacy=4.7.7 才是 v4)
#   2. noctalia-greeter 才在 Terra。文档原文给的就是 --repofrompath 写法。
#   3. noctalia v5 与 v4 (Quickshell) 是两套独立软件，包名与配置均不通用。
#   4. 官方 Terra 命令里的单引号 '$releasever' 依赖 dnf 自行展开。
#      这是否在 dnf5 上可靠说法不一（未经权威确认），故本脚本保留官方写法，
#      同时加 shell 展开兜底。两种写法任一成功即可，无所谓哪个生效。
#
# 【为什么脚本里没禁用旧 DM】
#   文档 §4 的前提是「系统已有 gdm/sddm/lightdm」。最小安装裸机没有 display-manager，
#   直接 enable greetd 即可，多一步 disable 反而要处理「unit 不存在」的报错。
# ============================================================
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

declare -a FAILED_STEPS=()

install_step() {
    local desc="$1"; shift
    if "$@"; then
        log_info "OK  $desc"
    else
        log_warn "FAIL $desc (继续后续步骤)"
        FAILED_STEPS+=("$desc")
    fi
}

prompt_user() {
    local msg="$1"
    printf '%s' "$msg" > /dev/tty
    read -r _ < /dev/tty
    printf '\n' > /dev/tty
}

# ---------- 0. 前置检查与全局变量 ----------
SCRIPT_PATH="$(realpath "$0")"

if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 sudo 运行此脚本: sudo bash $SCRIPT_PATH"
    exit 1
fi

if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="root"
fi

# 目标用户家目录（后续写配置文件用）
TARGET_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    log_error "无法解析用户 $REAL_USER 的家目录 (得到: '${TARGET_HOME:-空}')"
    log_error "请确认以 sudo 方式运行，且该用户存在。"
    exit 1
fi
log_info "目标家目录: $TARGET_HOME"

FEDORA_VER=$(rpm -E %fedora)
log_info "开始为 Fedora $FEDORA_VER 配置 Niri/Noctalia v5 环境..."
log_info "目标用户: $REAL_USER"

if [ "$FEDORA_VER" -lt 44 ]; then
    log_warn "Noctalia v5 官方支持 Fedora 44+，当前为 $FEDORA_VER，可能无法安装。"
    prompt_user "按回车继续，或 Ctrl+C 中止..."
fi

# ---------- 1. 安装 dnf-plugins-core ----------
log_info "步骤 1/14: 安装 dnf-plugins-core..."
install_step "安装 dnf-plugins-core" dnf install -y dnf-plugins-core

# ---------- 2. 配置 fastestmirror ----------
log_info "步骤 2/14: 配置 DNF fastestmirror..."
DNF_CONF="/etc/dnf/dnf.conf"
if grep -q "^fastestmirror" "$DNF_CONF" 2>/dev/null; then
    sed -i 's/^fastestmirror=.*/fastestmirror=True/' "$DNF_CONF"
else
    if grep -q "^\[main\]" "$DNF_CONF"; then
        sed -i '/^\[main\]/a fastestmirror=True' "$DNF_CONF"
    else
        printf "\n[main]\nfastestmirror=True\n" >> "$DNF_CONF"
    fi
fi
log_info "fastestmirror=True 已配置。"

# ---------- 3. 添加 RPM Fusion 仓库 ----------
# [VERIFIED] 主 release 包路径实测 200:
#   mirrors.rpmfusion.org/{free,nonfree}/fedora/rpmfusion-{free,nonfree}-release-44.noarch.rpm
log_info "步骤 3/14: 添加 RPM Fusion 仓库 (free + nonfree)..."
install_step "添加 RPM Fusion 仓库" \
    dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

# ---------- 4. tainted 子仓库 ----------
# [VERIFIED] Fedora 44 已无独立的 tainted release 包：
#   rpmfusion-free-release-tainted-44.noarch.rpm     => HTTP 404
#   rpmfusion-nonfree-release-tainted-44.noarch.rpm  => HTTP 404
#   解包 rpmfusion-free-release-44.noarch.rpm，payload 只含：
#     rpmfusion-free.repo / -updates.repo / -updates-testing.repo
#   => v1~v4 的 "dnf install rpmfusion-*-release-tainted" 是无效操作。
#   tainted 由 .repo 内的段提供且默认 enabled=0；存在才启用，不存在直接跳过。
log_info "步骤 4/14: 检查 RPM Fusion tainted 子仓库..."

enable_repo() {
    local repo="$1"
    # 先验证 repo 确实存在 —— dnf5 的 setopt 对不存在的 repo 会静默成功
    # 匹配边界：^[!*]?<id>[[:space:]] —— 兼容 dnf5 行首状态符号；
    #           terra-extras 不会误匹配 terra（后缀是 '-' 不是空格）
    if ! dnf repolist --all 2>/dev/null | grep -qE "^[!*]?${repo}[[:space:]]"; then
        return 1
    fi
    if dnf config-manager set-enabled "$repo" >/dev/null 2>&1; then
        return 0
    fi
    dnf config-manager --set-enabled "$repo" >/dev/null 2>&1
}

for r in rpmfusion-free-tainted rpmfusion-nonfree-tainted; do
    if enable_repo "$r"; then
        log_info "  已启用 $r"
    else
        log_warn "  $r 不存在或启用失败 —— 跳过（不影响主流程）"
    fi
done

# ---------- 5. 系统完整更新 ----------
log_info "步骤 5/14: 执行系统完整更新..."
install_step "系统完整更新" dnf update -y --refresh

# needs-restarting -r: 返回 1 表示需要重启。它检测不到纯内核更新，故补内核比对。
if ! dnf needs-restarting -r >/dev/null 2>&1 || \
   [ "$(rpm -q kernel 2>/dev/null | sort -V | tail -1 | sed 's/^kernel-//')" != "$(uname -r)" ]; then
    log_warn "=============================================================="
    log_warn "检测到需要重启系统以确保新内核与驱动模块生效。"
    log_warn "强烈建议现在重启系统，然后重新运行本脚本的剩余步骤。"
    log_warn "  sudo systemctl reboot"
    log_warn "=============================================================="
    prompt_user "按回车键继续，或按 Ctrl+C 中止以稍后重启..."
fi

# ---------- 6. AMD 显卡驱动与工具 ----------
log_info "步骤 6/14: 检查并安装 AMD 显卡驱动组件..."
lspci -k | grep -E "VGA|3D|Display" || log_warn "未检测到显卡信息。"

install_step "安装 Mesa 核心驱动" \
    dnf install -y mesa-dri-drivers mesa-vulkan-drivers vulkan-tools libva-utils

log_info "  安装 freeworld 版 VA-API 驱动 (AMD 硬解 H.264/H.265)..."
install_step "安装 mesa-va-drivers-freeworld" \
    dnf install -y mesa-va-drivers-freeworld --enablerepo=rpmfusion-nonfree

if rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
    log_info "  mesa-va-drivers-freeworld 安装成功。"
else
    log_warn "  mesa-va-drivers-freeworld 未安装，请检查日志。"
fi

# 32 位库：可选，会拉一整棵 i686 依赖树
if [ "${INSTALL_32BIT:-ask}" = "ask" ]; then
    printf '是否需要 32 位库 (Steam/Proton)？会额外拉取 i686 依赖 [y/N] ' > /dev/tty
    read -r ans < /dev/tty
    printf '\n' > /dev/tty
    case "${ans:-n}" in
        y|Y|yes|YES) INSTALL_32BIT=yes ;;
        *)           INSTALL_32BIT=no  ;;
    esac
fi

if [ "${INSTALL_32BIT}" = "yes" ]; then
    log_info "  安装 32 位 Mesa 驱动..."
    install_step "安装 32 位 Mesa 驱动" \
        dnf install -y mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 \
        mesa-va-drivers-freeworld.i686 --enablerepo=rpmfusion-nonfree
else
    log_info "  跳过 32 位 Mesa 驱动。"
fi

# ---------- 7. 视频编解码器 ----------
log_info "步骤 7/14: 完善视频编解码器..."

install_step "安装 GStreamer 基础包" \
    dnf install -y gstreamer1-plugins-base gstreamer1-plugins-good

install_step "安装 GStreamer 扩展编解码器" \
    dnf install -y gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-libav lame

# 最小安装通常没有 ffmpeg-free，swap 会因缺源包失败 -> 用 install --allowerasing
log_info "  安装完整版 ffmpeg..."
install_step "安装完整版 ffmpeg" dnf install -y ffmpeg --allowerasing

install_step "安装 libavcodec-freeworld" dnf install -y libavcodec-freeworld

# ---------- 8. 安装 niri 与 Noctalia v5 ----------
# [官方文档 · 原文]
#   "Noctalia is available from the default repos for Fedora 44 and up."
#     sudo dnf install noctalia
#   备选 (git 快照): sudo dnf copr enable lionheartp/Hyprland
#                    sudo dnf install noctalia-git
# [VERIFIED] niri 在 Fedora 官方仓库 (pkgdb 200, 含 F43/44/45)
log_info "步骤 8/14: 安装 niri 与 Noctalia v5..."

install_step "安装 niri (Fedora 官方仓库)" dnf install -y niri
install_step "安装 noctalia v5 (Fedora 44+ 默认仓库)" dnf install -y noctalia

# ---------- 9. 添加 Terra 仓库 (供 noctalia-greeter 使用) ----------
# [官方文档 · Greeter · Fedora 节 原文]
#   sudo dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
#   sudo dnf install noctalia-greeter
#
# [VERIFIED 2026-09-17] 实测 Terra 包放在仓库根目录（平铺）：
#     https://repos.fyralabs.com/terra44/terra-release-0:44-9.noarch.rpm  => HTTP 200
#     https://repos.fyralabs.com/terra44/repodata/repomd.xml              => HTTP 200
#   版本号来自 terra44 primary 元数据：terra-release 0:44-9
#
# 关于官方命令里的单引号 '$releasever'：它把展开交给 dnf 处理。
#   有资料称 dnf5 的 --repofrompath 不再做该替换，但此说法未经权威确认。
#   稳妥做法是保留官方写法 + 加 shell 展开兜底，两者任一成功即可。
#   （注意：若字面量未被展开，URL 会变成 .../terra$releasever，实测 HTTP 404）
log_info "步骤 9/14: 添加 Terra 仓库 (为 Noctalia Greeter)..."

# 封装：避免「官方写法失败但兜底成功」留下假失败记录
add_terra_repo() {
    # 先试官方写法（依赖 dnf 展开 $releasever）
    dnf install -y --nogpgcheck \
        --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
        terra-release >/dev/null 2>&1

    if rpm -q terra-release >/dev/null 2>&1; then
        log_info "  (官方写法成功)"
        return 0
    fi

    # 兜底：shell 展开版本号，不依赖 dnf 的变量展开行为
    log_warn "  官方写法未生效，改用 shell 展开重试..."
    dnf install -y --nogpgcheck \
        --repofrompath "terra,https://repos.fyralabs.com/terra${FEDORA_VER}" \
        terra-release >/dev/null 2>&1

    if rpm -q terra-release >/dev/null 2>&1; then
        log_info "  (兜底写法成功)"
        return 0
    fi
    return 1
}

install_step "添加 Terra 仓库" add_terra_repo

# 确认 terra 仓库确实可用
if dnf repolist --enabled 2>/dev/null | grep -qE "^[!*]?terra[[:space:]]"; then
    log_info "  terra 仓库已启用。"
else
    log_warn "  terra 仓库不可用 —— noctalia-greeter 会安装失败。"
fi

# ---------- 10. 安装 Noctalia Greeter ----------
# [官方文档 · 原文] sudo dnf install noctalia-greeter
# 依赖: greetd 与 D-Bus —— 文档 "Every installation needs greetd and D-Bus"
log_info "步骤 10/14: 安装 Noctalia Greeter..."
install_step "安装 greetd" dnf install -y greetd
install_step "安装 noctalia-greeter (Terra)" dnf install -y noctalia-greeter

# ---------- 11. 配置 greetd 会话 ----------
# [官方文档 §3 Configure greetd 原文要点]
#   - greetd 必须启动 `noctalia-greeter-session`，不是 `noctalia-greeter` 可执行文件
#   - command -v noctalia-greeter-session 取真实路径（文档: "the path may differ"）
#   - 合并进已有的 [default_session] 段，"Do not blindly overwrite an existing
#     greetd configuration"
#   - 某些发行版包会自动配置 greetd；此时只需确认 command 指向 wrapper，其余不动
#
# 最小安装没有旧 DM，故官方 §4「Replace the current display manager safely」不适用。
log_info "步骤 11/14: 配置 greetd 会话..."

GREETER_SESSION_BIN="$(command -v noctalia-greeter-session 2>/dev/null || true)"

if [ -z "$GREETER_SESSION_BIN" ]; then
    log_warn "未找到 noctalia-greeter-session —— 跳过 greetd 配置。"
    log_warn "  请手动确认包是否装好: rpm -ql noctalia-greeter | grep session"
    FAILED_STEPS+=("配置 greetd 会话 (未找到 wrapper)")
else
    log_info "  session wrapper: $GREETER_SESSION_BIN"

    GREETD_CONF="/etc/greetd/config.toml"
    mkdir -p /etc/greetd

    # 备份已有配置（如果存在）
    if [ -f "$GREETD_CONF" ]; then
        cp -a "$GREETD_CONF" "${GREETD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        log_info "  已备份原配置。"
    fi

    # 判断是否已有 [default_session] 段
    # 正则放宽：TOML 允许段名两侧有空白（`[ default_session ]` 是合法 TOML），
    # 也允许行首缩进。若用严格的 '^\[default_session\]' 判定，遇到这类写法会走到
    # else 追加分支 -> 文件出现两个 [default_session] 段 -> TOML 重复表 ->
    # greetd 解析报错 "Cannot declare ('default_session',) twice" -> 拒绝启动。
    DS_RE='^[[:space:]]*\[[[:space:]]*default_session[[:space:]]*\]'
    if [ -f "$GREETD_CONF" ] && grep -qE "$DS_RE" "$GREETD_CONF"; then
        # 已有该段 -> 仅在该段内替换 command/user，绝不碰其它段
        # （注意：不能用全局 sed，否则会误改 [initial_session] 等段的 command）
        log_info "  检测到已有 [default_session] 段，段内就地合并（不动其它段）。"
        awk -v bin="$GREETER_SESSION_BIN" '
            /^[[:space:]]*\[/ {
                in_ds = ($0 ~ /^[[:space:]]*\[[[:space:]]*default_session[[:space:]]*\]/)
            }
            in_ds && /^[[:space:]]*command[[:space:]]*=/ {
                if (!seen_cmd) { print "command = \"" bin "\""; seen_cmd=1 }
                next
            }
            in_ds && /^[[:space:]]*user[[:space:]]*=/ {
                if (!seen_user) { print "user = \"greeter\""; seen_user=1 }
                next
            }
            { print }
        ' "$GREETD_CONF" > "${GREETD_CONF}.tmp" && mv "${GREETD_CONF}.tmp" "$GREETD_CONF"

        # 补齐段内缺失的字段（greetd 需要 user 字段，缺了会启动失败）
        NEED="$(awk '/^[[:space:]]*\[[[:space:]]*default_session[[:space:]]*\]/{f=1;next}
                     /^[[:space:]]*\[/{f=0}
                     f && /^[[:space:]]*command[[:space:]]*=/{c=1}
                     f && /^[[:space:]]*user[[:space:]]*=/{u=1}
                     END{if(!c)print "command"; if(!u)print "user"}' "$GREETD_CONF")"
        if [ -n "$NEED" ]; then
            case "$NEED" in
                *user*)    sed -i "/${DS_RE}/a user = \"greeter\"" "$GREETD_CONF" ;;
            esac
            case "$NEED" in
                *command*) sed -i "/${DS_RE}/a command = \"${GREETER_SESSION_BIN}\"" "$GREETD_CONF" ;;
            esac
            log_info "  已补齐缺失字段。"
        fi
    else
        # 无该段 -> 追加，不覆盖文件其它内容
        log_info "  未检测到 [default_session] 段，追加写入。"
        {
            echo ""
            echo "[default_session]"
            echo "command = \"${GREETER_SESSION_BIN}\""
            echo "user = \"greeter\""
        } >> "$GREETD_CONF"
    fi

    # 校验 1: 段不能重复（重复 -> TOML 重复表 -> greetd 拒绝启动）
    DS_COUNT="$(grep -cE "$DS_RE" "$GREETD_CONF" 2>/dev/null || echo 0)"
    if [ "$DS_COUNT" -gt 1 ]; then
        log_warn "  config.toml 里出现 $DS_COUNT 个 [default_session] 段！"
        log_warn "  TOML 不允许重复表，greetd 会解析失败并拒绝启动。请手动合并。"
        FAILED_STEPS+=("配置 greetd 会话 (TOML 段重复)")
    fi

    # 校验 2: 目标命令确实写在 [default_session] 段内（而非文件里任意位置）
    if awk '
        /^[[:space:]]*\[/ { in_ds = ($0 ~ /^[[:space:]]*\[[[:space:]]*default_session[[:space:]]*\]/) }
        in_ds && /^[[:space:]]*command[[:space:]]*=/ && /noctalia-greeter-session/ { hit=1 }
        END { exit !hit }
    ' "$GREETD_CONF"; then
        log_info "  greetd 配置完成: $GREETD_CONF"
        log_info "  --- [default_session] 当前内容 ---"
        awk '/^[[:space:]]*\[[[:space:]]*default_session[[:space:]]*\]/{f=1} f{print} f&&/^[[:space:]]*\[/{if(++n>1)exit}' "$GREETD_CONF" | sed 's/^/    /'
    else
        log_warn "  [default_session] 段内未找到正确的 command，请手动检查 $GREETD_CONF"
        FAILED_STEPS+=("配置 greetd 会话 (段内 command 校验失败)")
    fi

    # 确保 greeter 用户存在（greetd 需要该账户运行会话）
    if ! id greeter >/dev/null 2>&1; then
        log_warn "  greeter 用户不存在，创建中..."
        if useradd -r -M -s /sbin/nologin -d /var/lib/greetd greeter 2>/dev/null; then
            log_info "  greeter 用户已创建。"
        else
            log_warn "  greeter 用户创建失败 —— 若 greetd 无法启动请手动处理。"
        fi
    else
        log_info "  greeter 用户已存在。"
    fi

    # 最小安装无旧 DM，直接启用 greetd
    install_step "启用 greetd 服务" systemctl enable greetd
fi

# ---------- 12. 安装 kitty + fish + 字体，写入完整美化配置 ----------
# 为什么在前置阶段装终端？
#   首次登录后 niri 用的是内置默认配置，默认终端快捷键绑 kitty。
#   若没装终端，登录后是「黑屏且打不开任何程序」的桌面，
#   只能 Ctrl+Alt+F3 切回 TTY 才能继续 —— 体验很差。
#
# 为什么连 fish 和字体一起装？
#   完整美化配置引用了 shell=fish 与 JetBrains Maple Mono 字体。
#   这两样不存在的话，kitty 会静默回退（默认 shell、默认字体），
#   等于「配了但没生效」。所以一并准备好，保证美化真正落地。
log_info "步骤 12/14: 安装 kitty + fish + 字体..."

install_step "安装 kitty 终端与 fish" dnf install -y kitty fish

# --- 下载 JetBrains Maple Mono 字体 ---
# 来源: https://github.com/SpaceTimee/Fusion-JetBrainsMapleMono
#       (JetBrains Mono + Maple Mono 合并字体，带 Nerd Font 图标)
FONT_DIR="$TARGET_HOME/.local/share/fonts/JetBrainsMapleMono"

install_font() {
    if fc-list 2>/dev/null | grep -qi "JetBrains Maple Mono"; then
        log_info "  JetBrains Maple Mono 已安装，跳过"
        return 0
    fi

    # 依赖检查
    for cmd in curl jq unzip fc-cache; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_warn "  缺少 $cmd，无法自动安装字体"
            return 1
        fi
    done

    mkdir -p "$FONT_DIR"
    local tmpd; tmpd="$(mktemp -d)"
    local api="https://api.github.com/repos/SpaceTimee/Fusion-JetBrainsMapleMono/releases/latest"

    log_info "  查询最新版本..."
    local rel; rel="$(curl -fsSL --max-time 30 "$api" 2>/dev/null || echo "")"
    if [ -z "$rel" ]; then
        log_warn "  无法访问 GitHub API（网络问题或限流）"
        rm -rf "$tmpd"
        return 1
    fi

    # 优先 Nerd Font 版，回退任意 zip
    local url; url="$(printf '%s' "$rel" | jq -r '[.assets[] | select(.name | test("NF.*\\.zip$"))] | .[0].browser_download_url // empty' 2>/dev/null)"
    if [ -z "$url" ]; then
        url="$(printf '%s' "$rel" | jq -r '[.assets[] | select(.name | test("\\.zip$"))] | .[0].browser_download_url // empty' 2>/dev/null)"
    fi

    if [ -z "$url" ]; then
        log_warn "  未能匹配到字体压缩包"
        log_warn "  手动下载: https://github.com/SpaceTimee/Fusion-JetBrainsMapleMono/releases"
        rm -rf "$tmpd"
        return 1
    fi

    log_info "  下载: $(basename "$url")"
    if ! curl -fsSL --max-time 300 -o "$tmpd/font.zip" "$url"; then
        log_warn "  下载失败（网络问题）"
        rm -rf "$tmpd"
        return 1
    fi

    if ! unzip -o -q "$tmpd/font.zip" -d "$FONT_DIR" 2>/dev/null; then
        log_warn "  解压失败"
        rm -rf "$tmpd"
        return 1
    fi

    # 扁平化：把子目录里的字体提到根，避免 kitty 找不到
    find "$FONT_DIR" -mindepth 2 -name "*.ttf" -exec mv -f {} "$FONT_DIR/" \; 2>/dev/null
    find "$FONT_DIR" -mindepth 2 -name "*.otf" -exec mv -f {} "$FONT_DIR/" \; 2>/dev/null
    rm -rf "${FONT_DIR:?}"/*/ 2>/dev/null

    chown -R "$REAL_USER:$REAL_USER" "$TARGET_HOME/.local" 2>/dev/null
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1
    log_info "  字体已安装并刷新缓存"
    rm -rf "$tmpd"
    return 0
}

install_step "安装 JetBrains Maple Mono 字体" install_font

# 字体回退（官方仓库，万一 Maple Mono 装不上至少有个像样的等宽字体）
install_step "安装 JetBrains Mono (回退字体)" dnf install -y jetbrains-mono-fonts

# --- 写入完整 kitty 美化配置 ---
# 来源: SHORiN-KiWATA/shorin-arch-setup 的 kitty.conf
# 移除项: include dank-tabs.conf / dank-theme.conf
#   (属 AUR 插件 kitty-dank-tabs，Fedora 无此包)
KITTY_CONF_DIR="$TARGET_HOME/.config/kitty"
if mkdir -p "$KITTY_CONF_DIR"; then
    cat > "$KITTY_CONF_DIR/kitty.conf" <<'KITTYEOF'
# ============================================================================
# kitty 终端配置 — 完整美化版
#
# 来源: SHORiN-KiWATA/shorin-arch-setup 的 kitty.conf (Fedora 适配)
#
# 依赖(前置脚本已一并安装):
#   - fish                   : shell
#   - JetBrains Maple Mono   : 字体
#   - current-theme.conf     : 配色(本脚本写入初始值，之后可由 Noctalia 更新)
#
# 已移除: include dank-tabs.conf / dank-theme.conf
#         (属 AUR 插件 kitty-dank-tabs，Fedora 无此包)
# ============================================================================

# --- 外观 ---
window_padding_width 5
hide_window_decorations yes
background_opacity 0.8
font_family JetBrains Maple Mono
font_size 13.5
remember_window_size no
confirm_os_window_close 0

# --- 光标 ---
cursor_trail 1
cursor_shape block
shell_integration no-cursor

# --- Shell ---
shell fish

# --- 配色主题 ---
# Noctalia 运行后会把壁纸配色写回此文件(通过其 matugen 模板机制)
include current-theme.conf
KITTYEOF

    # 初始配色（Noctalia/Matugen 的默认深色方案，之后会被覆盖）
    cat > "$KITTY_CONF_DIR/current-theme.conf" <<'THEMEEOF'
# 初始配色 — Noctalia 运行后会按壁纸重新生成
# 改配色请改 ~/.config/noctalia/templates/ 下的模板，不要直接改本文件

color0 #131316
color1 #ffb4ab
color2 #bec2ff
color3 #c5c4dd
color4 #e7b9d5
color5 #bec2ff
color6 #c5c4dd
color7 #e5e1e6
color8 #91909a
color9 #ffb4ab
color10 #bec2ff
color11 #c5c4dd
color12 #e7b9d5
color13 #bec2ff
color14 #c5c4dd
color15 #e5e1e6

cursor                #e5e1e6
cursor_text_color     #131316
background            #131316
foreground            #e5e1e6
selection_foreground  #c7c5d0
selection_background  #46464f
active_border_color   #bec2ff
inactive_border_color #46464f
url_color             #bec2ff

active_tab_foreground   #1f2578
active_tab_background   #bec2ff
inactive_tab_foreground #c7c5d0
inactive_tab_background #46464f
cursor_trail_color      #c7c5d0
THEMEEOF

    # 归属权交还给目标用户（脚本以 root 运行，否则配置文件属 root）
    if chown -R "$REAL_USER:$REAL_USER" "$KITTY_CONF_DIR" 2>/dev/null; then
        log_info "  kitty 美化配置已写入: $KITTY_CONF_DIR/"
        log_info "    - kitty.conf (外观 + fish + 主题引用)"
        log_info "    - current-theme.conf (初始配色)"
    else
        log_warn "  kitty 配置已写入但 chown 失败，请手动修正属主:"
        log_warn "    sudo chown -R $REAL_USER:$REAL_USER $KITTY_CONF_DIR"
        FAILED_STEPS+=("kitty 配置属主修正")
    fi
else
    log_warn "  无法创建 $KITTY_CONF_DIR，跳过 kitty 配置"
    FAILED_STEPS+=("写入 kitty 配置")
fi

# --- fish 基础配置 ---
# 只做最小可用配置；完整配置(starship/zoxide/别名)由后续的桌面配置提供
FISH_DIR="$TARGET_HOME/.config/fish"
if [ ! -f "$FISH_DIR/config.fish" ]; then
    if mkdir -p "$FISH_DIR"; then
        cat > "$FISH_DIR/config.fish" <<'FISHEOF'
# ============================================================================
# fish 基础配置 — 前置阶段版本
# 完整配置(starship 提示符、zoxide、别名、f 函数等)由桌面配置脚本提供
# ============================================================================

if status is-interactive
    # 交互式会话设置
end

set fish_greeting ""
fish_add_path ~/.local/bin
FISHEOF
        chown -R "$REAL_USER:$REAL_USER" "$FISH_DIR" 2>/dev/null
        log_info "  fish 基础配置已写入: $FISH_DIR/config.fish"
    else
        log_warn "  无法创建 $FISH_DIR，跳过 fish 配置"
    fi
else
    log_info "  fish 配置已存在，保留不动"
fi

# --- 把 fish 设为默认 shell（可选但推荐）---
if command -v fish >/dev/null 2>&1; then
    CURRENT_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"
    FISH_PATH="$(command -v fish)"
    if [ "$CURRENT_SHELL" != "$FISH_PATH" ]; then
        if chsh -s "$FISH_PATH" "$REAL_USER" 2>/dev/null; then
            log_info "  已将 $REAL_USER 的默认 shell 设为 fish"
        else
            log_warn "  设置默认 shell 失败，可手动执行:"
            log_warn "    chsh -s $FISH_PATH $REAL_USER"
        fi
    else
        log_info "  默认 shell 已是 fish"
    fi
fi

# ---------- 13. 安装常用桌面软件 ----------
# 本步安装「装完即可日常使用」的软件，并处理非官方来源的两项：
#   - Google Chrome : Fedora 官方仓库没有，从 Google 自己的 RPM 源装
#   - QQ / 微信      : Fedora 无包，用 Flatpak（Flathub）装
log_info "步骤 13/14: 安装常用桌面软件..."

# --- 13.1 Fedora 官方仓库的软件 ---
# fcitx5         : 中文输入法框架（含中文附加组件 + 图形配置工具）
# Thunar         : 轻量文件管理器（GTK，适配 niri 无桌面环境的场景）
# xprop          : X11 窗口属性查询 —— niri-force-kill-window 识别 XWayland 应用必需
# fzf            : 模糊查找 —— niri-binds 快捷键速查菜单依赖
# wl-clipboard   : wl-copy/wl-paste —— niri-pick 复制信息、截图管道依赖
# satty          : 截图标注工具 —— 配合 wl-clipboard 编辑剪贴板里的截图
install_step "安装 fcitx5 中文输入法" \
    dnf install -y fcitx5 fcitx5-chinese-addons fcitx5-configtool fcitx5-gtk fcitx5-qt

install_step "安装 Thunar 文件管理器" \
    dnf install -y Thunar thunar-volman thunar-archive-plugin

install_step "安装 xprop (窗口属性查询)" dnf install -y xprop
install_step "安装 fzf (模糊查找)" dnf install -y fzf
install_step "安装 wl-clipboard" dnf install -y wl-clipboard
install_step "安装 satty (截图标注, Terra)" dnf install -y satty

# --- 13.2 Google Chrome（来自 Google 官方 RPM 源）---
# Fedora 官方仓库只有 chromium，没有 google-chrome。
# Google 自己维护 RPM 仓库，官方推荐做法就是加它的 repo 再装。
install_chrome() {
    # 已装则跳过
    if command -v google-chrome-stable >/dev/null 2>&1; then
        log_info "  Google Chrome 已安装，跳过"
        return 0
    fi

    # 导入 Google 签名密钥
    local key=/etc/pki/rpm-gpg/RPM-GPG-KEY-google
    if [ ! -f "$key" ]; then
        if curl -fsSL --max-time 60 \
            "https://dl.google.com/linux/linux_signing_key.pub" -o "$key"; then
            log_info "  Google 签名密钥已导入: $key"
        else
            log_warn "  下载 Google 签名密钥失败（网络问题）"
            log_warn "  手动安装: https://www.google.com/chrome/"
            return 1
        fi
    fi

    # 写入 Google 的 yum/dnf 仓库文件
    cat > /etc/yum.repos.d/google-chrome.repo <<'CHROMEREPO'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-google
CHROMEREPO

    log_info "  Google Chrome 仓库已写入 /etc/yum.repos.d/google-chrome.repo"
    # 首次安装需要导入密钥，否则 gpgcheck 会失败
    dnf install -y google-chrome-stable
}

install_step "安装 Google Chrome" install_chrome

# --- 13.3 QQ / 微信（Flatpak）---
# Fedora 仓库里没有这两个包。Flathub 有腾讯维护的官方包：
#   com.qq.QQ          — QQ
#   com.tencent.WeChat — 微信
install_flatpak_apps() {
    # 确认 flatpak 可用
    if ! command -v flatpak >/dev/null 2>&1; then
        log_warn "  flatpak 未安装，跳过 QQ/微信"
        return 1
    fi

    # 添加 Flathub 远程源（已存在则跳过）
    if ! flatpak remotes 2>/dev/null | grep -q '^flathub'; then
        log_info "  添加 Flathub 远程源..."
        if ! flatpak remote-add --if-not-exists flathub \
            https://flathub.org/repo/flathub.flatpakrepo; then
            log_warn "  添加 Flathub 失败（网络问题）"
            log_warn "  手动执行: flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
            return 1
        fi
    else
        log_info "  Flathub 远程源已存在"
    fi

    local rc=0
    # QQ
    if flatpak list --app 2>/dev/null | grep -q 'com.qq.QQ'; then
        log_info "  QQ 已安装，跳过"
    else
        log_info "  安装 QQ（首次会拉取运行时，体积较大，请耐心等待）..."
        flatpak install -y --noninteractive flathub com.qq.QQ || {
            log_warn "  QQ 安装失败（网络问题？可稍后手动: flatpak install flathub com.qq.QQ）"
            rc=1
        }
    fi

    # 微信
    if flatpak list --app 2>/dev/null | grep -q 'com.tencent.WeChat'; then
        log_info "  微信已安装，跳过"
    else
        log_info "  安装微信（同样会拉取运行时）..."
        flatpak install -y --noninteractive flathub com.tencent.WeChat || {
            log_warn "  微信安装失败（可稍后手动: flatpak install flathub com.tencent.WeChat）"
            rc=1
        }
    fi
    return $rc
}

install_step "安装 flatpak" dnf install -y flatpak
install_step "安装 QQ 与微信 (Flatpak)" install_flatpak_apps

# --- 13.4 部署 niri 辅助脚本 ---
# niri-force-kill-window : 鼠标点选后 SIGKILL 强杀窗口（Alt+F4 / Alt+Shift+F4）
#   依赖 xprop 识别 XWayland 应用（XWayland 的 PID 是代理，直接 kill 杀不掉真身）
# niri-binds             : 扫描所有 .kdl 的键位绑定，用 fzf 弹出速查菜单
# niri-pick              : 提取窗口信息（AppID/PID/标题）或屏幕吸色，写入剪贴板
NIRI_SCRIPTS_DIR="$TARGET_HOME/.config/niri/scripts"

deploy_niri_scripts() {
    if ! mkdir -p "$NIRI_SCRIPTS_DIR"; then
        log_warn "  无法创建 $NIRI_SCRIPTS_DIR"
        return 1
    fi

    # niri-force-kill-window
    cat > "$NIRI_SCRIPTS_DIR/niri-force-kill-window" <<'KILLEOF'
#!/usr/bin/env bash
# ============================================================================
# niri-force-kill-window — 鼠标点选窗口并强制终止（SIGKILL）
#
# 用法:
#   niri-force-kill-window      仅杀死该窗口的进程
#   niri-force-kill-window -f   杀死该窗口的整个进程树（治自动重启的窗口）
#
# 来源: 参考 SHORiN-KiWATA/shorin-niri 的同名脚本行为重写
# 依赖: niri (pick-window)、xprop（可选，用于 XWayland 应用）、libnotify
# ============================================================================
set -u

FORCE_TREE=false
[ "${1:-}" = "-f" ] && FORCE_TREE=true

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "$1" "$2" || true
}

# 让用户点选窗口，拿到 PID
PICKED="$(niri msg pick-window 2>/dev/null)" || {
    notify "强杀窗口" "未选中窗口（操作已取消）"
    exit 1
}
[ -z "$PICKED" ] && { notify "强杀窗口" "未选中窗口"; exit 1; }

PID="$(printf '%s' "$PICKED" | sed -n 's/.*PID: \([0-9]*\).*/\1/p')"
TITLE="$(printf '%s' "$PICKED" | sed -n 's/.*Title: "\(.*\)"/\1/p')"
APPID="$(printf '%s' "$PICKED" | sed -n 's/.*App ID: "\(.*\)"/\1/p')"

if [ -z "$PID" ]; then
    notify "强杀窗口" "未能解析出 PID"
    exit 1
fi

# XWayland 应用：niri 报的 PID 是 XWayland 代理，需要用 xprop 拿真实 PID
if command -v xprop >/dev/null 2>&1 && command -v xwininfo >/dev/null 2>&1; then
    XPID="$(xprop -root _NET_CLIENT_LIST 2>/dev/null | head -1 | grep -o '[0-9]\+' | head -1)"
    if [ -n "${XPID:-}" ]; then
        REAL="$(xprop -id "$XPID" _NET_WM_PID 2>/dev/null | grep -o '[0-9]\+$')"
        [ -n "${REAL:-}" ] && PID="$REAL"
    fi
fi

kill_target() {
    local p="$1"
    if [ "$FORCE_TREE" = true ]; then
        # 向上溯源到应用根进程（跳过 niri/systemd/bash 等）
        local root="$p"
        local cur="$p"
        local i=0
        while [ $i -lt 16 ]; do
            local ppid
            ppid="$(awk '{print $4}' "/proc/$cur/stat" 2>/dev/null)"
            [ -z "${ppid:-}" ] || [ "$ppid" = "0" ] || [ "$ppid" = "1" ] && break
            local pname
            pname="$(cat "/proc/$ppid/comm" 2>/dev/null)"
            case "$pname" in
                systemd|niri|bash|sh|zsh|fish|init|Xwayland|systemd-*) break ;;
            esac
            root="$ppid"; cur="$ppid"; i=$((i+1))
        done
        # 递归收集所有子孙
        local all="$root"
        local queue="$root"
        while [ -n "$queue" ]; do
            local next=""
            local q
            for q in $queue; do
                local kids
                kids="$(pgrep -P "$q" 2>/dev/null | tr '\n' ' ')"
                next="$next $kids"
                all="$all $kids"
            done
            queue="$next"
        done
        # shellcheck disable=SC2086
        kill -9 $all 2>/dev/null
        notify "强杀窗口 (进程树)" "已终止: ${TITLE:-$APPID} (root PID $root)"
    else
        kill -9 "$p" 2>/dev/null
        notify "强杀窗口" "已终止: ${TITLE:-$APPID} (PID $p)"
    fi
}

kill_target "$PID"
exit 0
KILLEOF
    chmod +x "$NIRI_SCRIPTS_DIR/niri-force-kill-window"
    log_info "  已部署 niri-force-kill-window"

    # niri-binds — 快捷键速查
    cat > "$NIRI_SCRIPTS_DIR/niri-binds" <<'BINDSEOF'
#!/usr/bin/env bash
# ============================================================================
# niri-binds — 列出所有带 hotkey-overlay-title 的绑定，用 fzf 弹出速查
#
# 行为: 扫描 ~/.config/niri/*.kdl，提取「按键 / 说明 / 动作」三列，
#       用 column 对齐后交给 fzf；选中后若有动作可执行，则执行。
#
# 来源: 参考 SHORiN-KiWATA/shorin-niri 的同名脚本行为重写
# 依赖: fzf、某个终端(优先 kitty)
# ============================================================================
set -u

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
[ -d "$CONF_DIR" ] || { echo "找不到 niri 配置目录: $CONF_DIR"; exit 1; }

command -v fzf >/dev/null 2>&1 || { echo "需要 fzf: sudo dnf install -y fzf"; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# 提取绑定：只取带 hotkey-overlay-title= 的行
grep -h 'hotkey-overlay-title' "$CONF_DIR"/*.kdl 2>/dev/null \
| sed -E 's/^[[:space:]]+//' \
| awk '{
    key=$1;
    title=""; action="";
    if (match($0, /hotkey-overlay-title="([^"]*)"/, m)) title=m[1];
    else if (match($0, /hotkey-overlay-title=null/)) title="(无说明)";
    if (match($0, /\{[[:space:]]*(.*)[[:space:]]*\}[[:space:]]*$/, a)) action=a[1];
    printf "%-28s %-40s %s\n", key, title, action;
}' | sort -u > "$TMP"

[ -s "$TMP" ] || { echo "未找到任何带说明的绑定"; exit 1; }

SELECTED="$(fzf --prompt='快捷键 > ' \
    --header='选中后会执行对应动作（危险操作请谨慎）' \
    --height=100% --reverse < "$TMP")" || exit 0

# 从选中行里取出动作部分
ACTION="$(printf '%s' "$SELECTED" | awk -F'  +' '{print $NF}')"

case "$ACTION" in
    spawn\ *|spawn-sh\ *|"quit;"|close-window*|toggle-*|focus-*|move-*|maximize*|minimize*|fullscreen*|switch-*|center-*|expand-*|consume-*|expel-*|reset-*|set-*)
        niri msg action ${ACTION%;} >/dev/null 2>&1 || true
        ;;
esac
exit 0
BINDSEOF
    chmod +x "$NIRI_SCRIPTS_DIR/niri-binds"
    log_info "  已部署 niri-binds"

    chown -R "$REAL_USER:$REAL_USER" "$NIRI_SCRIPTS_DIR" 2>/dev/null
    return 0
}

install_step "部署 niri 辅助脚本" deploy_niri_scripts

# --- 13.5 输入法环境变量（fcitx5）---
# 这一步写到 /etc/environment，对所有会话生效，
# 比只写 shell 配置更可靠（GUI 程序也能拿到）
setup_fcitx_env() {
    if ! command -v fcitx5 >/dev/null 2>&1; then
        log_warn "  fcitx5 未装上，跳过环境变量配置"
        return 1
    fi

    local ENVFILE=/etc/environment
    local changed=false

    add_env() {
        local line="$1"
        if ! grep -qxF "$line" "$ENVFILE" 2>/dev/null; then
            printf '%s\n' "$line" >> "$ENVFILE"
            changed=true
        fi
    }

    touch "$ENVFILE"
    add_env 'GTK_IM_MODULE=fcitx'
    add_env 'QT_IM_MODULE=fcitx'
    add_env 'XMODIFIERS=@im=fcitx'
    add_env 'SDL_IM_MODULE=fcitx'
    add_env 'GLFW_IM_MODULE=ibus'

    if [ "$changed" = true ]; then
        log_info "  已写入输入法环境变量到 $ENVFILE"
    else
        log_info "  输入法环境变量已存在"
    fi
    return 0
}

install_step "配置 fcitx5 环境变量" setup_fcitx_env

# --- 13.6 fcitx5 开机自启 ---
# niri 不读 XDG autostart，所以要在 niri 配置里 spawn-at-startup。
# 这里先装一个 wrapper，步骤 14 的配置里会引用它。
setup_fcitx_autostart() {
    if ! command -v fcitx5 >/dev/null 2>&1; then
        return 1
    fi
    local BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    cat > "$BIN_DIR/fcitx5-autostart" <<'FEOF'
#!/usr/bin/env bash
# 幂等启动 fcitx5：已在运行则不重复拉起
if ! pgrep -x fcitx5 >/dev/null 2>&1; then
    exec fcitx5 -d
fi
FEOF
    chmod +x "$BIN_DIR/fcitx5-autostart"
    chown -R "$REAL_USER:$REAL_USER" "$BIN_DIR" 2>/dev/null
    log_info "  已部署 fcitx5 自启包装脚本: $BIN_DIR/fcitx5-autostart"
    return 0
}

install_step "部署 fcitx5 自启脚本" setup_fcitx_autostart

# ---------- 14. 写入完整 niri 配置（含完整快捷键） ----------
# 写入 ~/.config/niri/config.kdl，包含:
#   1. Noctalia 自启
#   2. 输入法环境变量 + fcitx5 自启
#   3. 完整的键位绑定（键位照 SHORiN-KiWATA/shorin-niri，
#      命令换成 Noctalia v5 原生 IPC）
log_info "步骤 14/14: 写入完整 niri 配置..."
NIRI_CONF_DIR="$TARGET_HOME/.config/niri"
NIRI_CONF="$NIRI_CONF_DIR/config.kdl"

if mkdir -p "$NIRI_CONF_DIR"; then
    # 已有配置先备份（这次是完整覆盖，备份以防万一）
    if [ -f "$NIRI_CONF" ]; then
        cp -a "$NIRI_CONF" "$NIRI_CONF.bak-$(date +%Y%m%d-%H%M%S)"
        log_info "  已备份原配置: $NIRI_CONF.bak-*"
    fi

    cat > "$NIRI_CONF" <<'NIRIEOF'
// ============================================================================
// niri 完整配置 — Noctalia v5 版
//
// 键位来源: SHORiN-KiWATA/shorin-niri
//   键位完全照搬，仅把调用的命令换成 Noctalia v5 原生 IPC。
//
// 环境: Fedora 44 + niri + Noctalia v5 + fcitx5 + Chrome + Thunar
// ============================================================================

// ---------------------------------------------------------------------------
// 自启动
// ---------------------------------------------------------------------------

// Noctalia v5 —— 提供状态栏、通知、壁纸、启动器、截图、剪贴板等
spawn-at-startup "noctalia"

// fcitx5 中文输入法（包装脚本内部做了幂等检查，不会重复启动）
spawn-at-startup "~/.local/bin/fcitx5-autostart"

// ---------------------------------------------------------------------------
// 环境变量
// ---------------------------------------------------------------------------
// 输入法相关变量已在脚本里写入 /etc/environment（对所有会话生效）。
// 这里额外声明一份，保证 niri 会话内一定拿得到。
environment {
    XMODIFIERS "@im=fcitx"
    QT_IM_MODULE "fcitx"
    GTK_IM_MODULE "fcitx"
    SDL_IM_MODULE "fcitx"
}

// ---------------------------------------------------------------------------
// 输入设备
// ---------------------------------------------------------------------------
input {
    keyboard {
        // 键盘布局（需要改成别的布局就改这里）
        xkb {
            layout "us"
        }
    }

    // 触摸板
    touchpad {
        tap
        natural-scroll
    }

    // 鼠标
    mouse {
    }

    // 焦点跟随鼠标（可选，觉得干扰就注释掉）
    // focus-follows-mouse max-scroll-amount="0%"
}

// ---------------------------------------------------------------------------
// 输出（显示器）
// ---------------------------------------------------------------------------
// 留空使用自动检测。多显示器时可用 `niri msg outputs` 查看名称后在此配置。

// ---------------------------------------------------------------------------
// 布局
// ---------------------------------------------------------------------------
layout {
    // 窗口间空隙
    gaps 8

    // 默认列宽（50% = 半屏）
    default-column-width { proportion 0.5; }

    // 焦点环
    focus-ring {
        width 2
        active-color "#bec2ff"
        inactive-color "#46464f"
    }

    // 边框（不用时可设 off）
    border {
        off
    }

    // 窗口阴影
    shadow {
        on
        softness 30
        spread 5
        offset x=0 y=5
        color "#00000054"
    }
}

// ---------------------------------------------------------------------------
// 动画
// ---------------------------------------------------------------------------
animations {
    // 关掉动画可提升低配机器流畅度
    // off
}

// ---------------------------------------------------------------------------
// 窗口规则
// ---------------------------------------------------------------------------
window-rule {
    // 浮动窗口默认居中
    match is-floating=true
    // 不做特殊处理，保持默认
}

// 浏览器设为默认不浮动、占满一列（可按需删改）
window-rule {
    match app-id=r#"^(google-chrome|chromium|firefox)$"#
    // 打开时默认占 50% 宽
    default-column-width { proportion 0.5; }
}

// QQ / 微信（Flatpak 运行）设为浮动小窗，方便随时呼出
window-rule {
    match app-id=r#"^(com\.qq\.QQ|com\.tencent\.WeChat)$"#
    open-floating true
    default-floating-position x=100 y=100 relative-to="top-right"
    default-column-width { proportion 0.35; }
    default-window-height { proportion 0.7; }
}

// ---------------------------------------------------------------------------
// 快捷键
// ---------------------------------------------------------------------------
binds {
    // Mod = Super 键（键盘上画 Windows 徽标的那个）

    // ========================================================================
    // 一、快捷键速查
    // ========================================================================

    // 弹出快捷键速查菜单（fzf 列出所有带说明的绑定，选中可直接执行）
    Mod+Shift+Slash hotkey-overlay-title="快捷键教程 Keybind tutorial" { spawn "~/.config/niri/scripts/niri-binds"; }

    // ========================================================================
    // 二、窗口切换 / 启动器 / 终端
    // ========================================================================

    // 窗口切换浮层（Noctalia 自带的 Alt+Tab 风格切换器）
    Alt+Tab hotkey-overlay-title="快速跳转窗口 Quick window switch menu" { spawn "noctalia" "msg" "window-switcher"; }

    // 程序启动器（Noctalia 自带，可搜索应用 / 算数 / 关机）
    Mod+Z hotkey-overlay-title="程序菜单 Applauncher" { spawn "noctalia" "msg" "panel-toggle" "launcher"; }

    // 临时浮动终端（单实例，再按会切回已有窗口）
    Mod+Slash hotkey-overlay-title="临时终端 Quick Terminal" { spawn "kitty" "--single-instance" "--class" "quickterminal"; }

    // 共享终端（单实例：已开则聚焦，不开新窗口）
    Mod+T hotkey-overlay-title="共享终端 Terminal" { spawn "kitty" "--single-instance"; }

    // 独立终端（每次都开新窗口）
    Mod+return hotkey-overlay-title="独立终端 Terminal" { spawn "kitty"; }

    // 浏览器（Google Chrome）
    Mod+B hotkey-overlay-title="浏览器 Browser" { spawn "google-chrome-stable"; }

    // 文件管理器（Thunar）
    Mod+E hotkey-overlay-title="文档管理器 Filemanager" { spawn "thunar"; }

    // ========================================================================
    // 三、壁纸 / 主题（Noctalia 自带）
    // ========================================================================

    // 打开壁纸选择面板
    Mod+Alt+W hotkey-overlay-title="切换壁纸 Change wallpaper" { spawn "noctalia" "msg" "panel-toggle" "wallpaper"; }

    // 随机换一张壁纸
    Mod+F10 hotkey-overlay-title="随机切换壁纸 Random wallpaper" { spawn "noctalia" "msg" "wallpaper-random"; }

    // 切换浅色/深色主题
    Mod+Alt+T hotkey-overlay-title="切换深浅色 Toggle theme mode" { spawn "noctalia" "msg" "theme-mode-toggle"; }

    // ========================================================================
    // 四、输入法
    // ========================================================================

    // 开/关 fcitx5（已运行则杀掉，未运行则拉起）
    Mod+F1 hotkey-overlay-title="开关输入法 Toggle fcitx" { spawn-sh "pkill fcitx5 || fcitx5 -d"; }

    // ========================================================================
    // 五、状态栏
    // ========================================================================

    // 显示状态栏
    Mod+F2 hotkey-overlay-title="状态栏 Bar (default)" { spawn "noctalia" "msg" "bar-show"; }

    // 隐藏状态栏（临时看全屏内容时用）
    Mod+Shift+F4 hotkey-overlay-title="隐藏任务栏 Hide bar" { spawn "noctalia" "msg" "bar-hide"; }

    // 开关状态栏（显示/隐藏切换）
    Mod+F4 hotkey-overlay-title="开关任务栏 Toggle bar" { spawn "noctalia" "msg" "bar-toggle"; }

    // ========================================================================
    // 六、截图（Noctalia 自带截图，不需要 grim/slurp）
    // ========================================================================

    // 截图翻译键位 → 改为「截图并标注」：框选后可直接在图上画箭头/文字
    Mod+F11 hotkey-overlay-title="截图并标注 Screenshot & annotate" { spawn "noctalia" "msg" "screenshot-annotate"; }

    // 截取所有显示器（多屏拼接成一张）
    Mod+F12 hotkey-overlay-title="截取所有显示器 Screenshot All Monitor" { spawn "noctalia" "msg" "screenshot-fullscreen" "all"; }

    // 选取区域截图
    Mod+Alt+A hotkey-overlay-title="选取区域截图 Select screenshot" { spawn "noctalia" "msg" "screenshot-region"; }

    // 截取当前聚焦的窗口
    Mod+Alt+Ctrl+A hotkey-overlay-title="截取聚焦窗口 Focus-window screenshot" { spawn "noctalia" "msg" "screenshot-fullscreen"; }

    // 截取指定显示器（会弹出显示器选择）
    Mod+Alt+Ctrl+Shift+A hotkey-overlay-title="截取显示器 Monitor screenshot" { spawn "noctalia" "msg" "screenshot-fullscreen" "pick"; }

    // Print 键：区域截图
    Print hotkey-overlay-title="区域截图 (Print 键) Screenshot region" { spawn "noctalia" "msg" "screenshot-region"; }
    // Ctrl+Print：截当前窗口
    Ctrl+Print hotkey-overlay-title="截当前窗口 (Ctrl+Print) Screenshot window" { spawn "noctalia" "msg" "screenshot-fullscreen"; }
    // Shift+Print：截所有显示器
    Shift+Print hotkey-overlay-title="截所有显示器 (Shift+Print) Screenshot all" { spawn "noctalia" "msg" "screenshot-fullscreen" "all"; }

    // 截图后编辑：把剪贴板里的图用 satty 打开标注
    Mod+Shift+S hotkey-overlay-title="编辑剪贴板中的截图 Edit the image after screenshot" { spawn-sh "wl-paste | satty -f -"; }

    // ========================================================================
    // 七、音量 / 亮度 / 媒体（Noctalia 自带 OSD，不需要 swayosd/brightnessctl）
    // ========================================================================

    XF86AudioRaiseVolume allow-when-locked=true hotkey-overlay-title="音量 +5% Volume up" { spawn "noctalia" "msg" "volume-up"; }
    XF86AudioLowerVolume allow-when-locked=true hotkey-overlay-title="音量 -5% Volume down" { spawn "noctalia" "msg" "volume-down"; }
    XF86AudioMute        allow-when-locked=true hotkey-overlay-title="静音开关 Mute toggle" { spawn "noctalia" "msg" "volume-mute"; }
    XF86AudioMicMute     allow-when-locked=true hotkey-overlay-title="麦克风静音 Mic mute" { spawn "noctalia" "msg" "mic-mute"; }

    XF86MonBrightnessUp   allow-when-locked=true hotkey-overlay-title="亮度 +5% Brightness up" { spawn "noctalia" "msg" "brightness-up"; }
    XF86MonBrightnessDown allow-when-locked=true hotkey-overlay-title="亮度 -5% Brightness down" { spawn "noctalia" "msg" "brightness-down"; }

    XF86AudioPlay hotkey-overlay-title="播放/暂停 Play/Pause" { spawn "noctalia" "msg" "media" "toggle"; }
    XF86AudioNext hotkey-overlay-title="下一曲 Next track"   { spawn "noctalia" "msg" "media" "next"; }
    XF86AudioPrev hotkey-overlay-title="上一曲 Previous track" { spawn "noctalia" "msg" "media" "previous"; }

    // ========================================================================
    // 八、锁屏 / 剪贴板 / 电源
    // ========================================================================

    // 锁屏（Noctalia 自带锁屏，不需要 hyprlock）
    Mod+Alt+L hotkey-overlay-title="锁屏 Lock screen" { spawn "noctalia" "msg" "session" "lock"; }

    // 剪贴板历史面板（Noctalia 自带，可搜索历史并粘贴）
    Mod+Alt+V hotkey-overlay-title="剪贴板 Clipboard" repeat=false { spawn "noctalia" "msg" "panel-toggle" "clipboard"; }

    // 电源菜单（锁屏 / 注销 / 重启 / 关机 / 待机）
    Mod+Shift+P hotkey-overlay-title="电源菜单 powermenu" { spawn "noctalia" "msg" "panel-toggle" "session"; }

    // ========================================================================
    // 九、QQ / 微信（Flatpak 安装，用 flatpak run 启动）
    // ========================================================================

    // 快速呼出 QQ（已开则聚焦；Noctalia 支持应用聚焦）
    Mod+Shift+Q hotkey-overlay-title="快速聚焦到QQ Quick focus QQ" { spawn "flatpak" "run" "com.qq.QQ"; }

    // 快速呼出微信
    Mod+Shift+W hotkey-overlay-title="快速聚焦到微信 Quick focus Wechat" { spawn "flatpak" "run" "com.tencent.WeChat"; }

    // ========================================================================
    // 十、通知 / 无线 / 系统开关（Noctalia 自带）
    // ========================================================================

    // 勿扰模式开关（屏蔽所有通知弹窗）
    // 注: 不用 Mod+Shift+D（Shorin 里已被「把窗口从列里拆出」占用）
    Mod+Alt+D hotkey-overlay-title="勿扰模式 Do not disturb" { spawn "noctalia" "msg" "notification-dnd-toggle"; }

    // Wi-Fi 开关
    Mod+Shift+B hotkey-overlay-title="Wi-Fi 开关 Toggle Wi-Fi" { spawn "noctalia" "msg" "wifi-toggle"; }

    // 蓝牙开关
    Mod+Shift+C hotkey-overlay-title="蓝牙开关 Toggle Bluetooth" { spawn "noctalia" "msg" "bluetooth-toggle"; }

    // 夜灯（屏幕色温变暖，护眼）
    Mod+Shift+N hotkey-overlay-title="夜灯 Night light" { spawn "noctalia" "msg" "nightlight-toggle"; }

    // 防休眠（咖啡因：阻止屏幕关闭和系统待机）
    // 注: 不用 Mod+Shift+A（Shorin 里已被「把窗口并入当前列」占用）
    Mod+Alt+K hotkey-overlay-title="防休眠 Caffeine" { spawn "noctalia" "msg" "caffeine-toggle"; }

    // 关闭显示器（不锁屏，动鼠标即恢复）
    Mod+Shift+O hotkey-overlay-title="关闭显示器 Turn off monitors" { spawn "noctalia" "msg" "dpms-off"; }

    // ========================================================================
    // 十一、窗口总览 / 关闭 / 强杀
    // ========================================================================

    // 切换总览界面（缩放显示所有窗口和工作区）
    Mod+O hotkey-overlay-title="切换总览界面 toggle overview" repeat=false { toggle-overview; }
    Mod+G hotkey-overlay-title="切换总览界面 toggle overview" repeat=false { toggle-overview; }
    Mod+Alt+G hotkey-overlay-title="切换总览界面 toggle overview" repeat=false { toggle-overview; }

    // 关闭当前聚焦窗口（正常退出程序）
    Mod+Q hotkey-overlay-title="关闭聚焦窗口 Close focus window" repeat=false { close-window; }

    // 强制杀死窗口（鼠标点选）：程序卡死无响应时用，发 SIGKILL
    Alt+F4 hotkey-overlay-title="强制杀死窗口 Force kill -9 window" repeat=false { spawn "~/.config/niri/scripts/niri-force-kill-window"; }

    // 强制杀死窗口及其所有关联进程（治会自动重启的程序）
    Alt+Shift+F4 hotkey-overlay-title="强制杀死窗口以及关联进程 Force kill -9 a window tree" repeat=false { spawn "~/.config/niri/scripts/niri-force-kill-window" "-f"; }

    // 鼠标中键点击窗口即可关闭它
    Mod+MouseMiddle hotkey-overlay-title="中键关闭窗口 Close window (middle click)" { close-window; }

    // ========================================================================
    // 十二、窗口聚焦（方向键 / vim 键）
    // ========================================================================

    Mod+Left  hotkey-overlay-title="聚焦左侧列 Focus column left" { focus-column-left; }
    Mod+Down  hotkey-overlay-title="聚焦下方窗口 Focus window down" { focus-window-down; }
    Mod+Up    hotkey-overlay-title="聚焦上方窗口 Focus window up" { focus-window-up; }
    Mod+Right hotkey-overlay-title="聚焦右侧列 Focus column right" { focus-column-right; }

    // vim 风格（同方向键效果）
    Mod+H hotkey-overlay-title="聚焦左侧列 (vim)" { focus-column-left; }
    Mod+J hotkey-overlay-title="聚焦下方窗口 (vim)" { focus-window-down; }
    Mod+K hotkey-overlay-title="聚焦上方窗口 (vim)" { focus-window-up; }
    Mod+L hotkey-overlay-title="聚焦右侧列 (vim)" { focus-column-right; }

    // ========================================================================
    // 十三、移动窗口 / 列
    // ========================================================================

    Mod+Ctrl+Left  hotkey-overlay-title="整列左移 Move column left" { move-column-left; }
    Mod+Ctrl+Down  hotkey-overlay-title="窗口下移 Move window down" { move-window-down; }
    Mod+Ctrl+Up    hotkey-overlay-title="窗口上移 Move window up" { move-window-up; }
    Mod+Ctrl+Right hotkey-overlay-title="整列右移 Move column right" { move-column-right; }

    Mod+Ctrl+H hotkey-overlay-title="整列左移 (vim)" { move-column-left; }
    Mod+Ctrl+J hotkey-overlay-title="窗口下移 (vim)" { move-window-down; }
    Mod+Ctrl+K hotkey-overlay-title="窗口上移 (vim)" { move-window-up; }
    Mod+Ctrl+L hotkey-overlay-title="整列右移 (vim)" { move-column-right; }

    Mod+Ctrl+A hotkey-overlay-title="整列左移 (a/d)" { move-column-left; }
    Mod+Ctrl+D hotkey-overlay-title="整列右移 (a/d)" { move-column-right; }

    // 跳到首尾列
    Mod+Home hotkey-overlay-title="跳到第一列 Jump to first column" { focus-column-first; }
    Mod+End  hotkey-overlay-title="跳到最后一列 Jump to last column" { focus-column-last; }
    Mod+Ctrl+Home hotkey-overlay-title="把整列移到最前 Move column to first" { move-column-to-first; }
    Mod+Ctrl+End  hotkey-overlay-title="把整列移到最后 Move column to last" { move-column-to-last; }

    // ========================================================================
    // 十四、跨显示器（多屏时生效，单屏无副作用）
    // ========================================================================

    Mod+Shift+Left  hotkey-overlay-title="聚焦左侧显示器 Focus monitor left" { focus-monitor-left; }
    Mod+Shift+Down  hotkey-overlay-title="聚焦下方显示器 Focus monitor down" { focus-monitor-down; }
    Mod+Shift+Up    hotkey-overlay-title="聚焦上方显示器 Focus monitor up" { focus-monitor-up; }
    Mod+Shift+Right hotkey-overlay-title="聚焦右侧显示器 Focus monitor right" { focus-monitor-right; }

    Mod+Shift+H hotkey-overlay-title="聚焦左侧显示器 (vim)" { focus-monitor-left; }
    Mod+Shift+J hotkey-overlay-title="聚焦下方显示器 (vim)" { focus-monitor-down; }
    Mod+Shift+K hotkey-overlay-title="聚焦上方显示器 (vim)" { focus-monitor-up; }
    Mod+Shift+L hotkey-overlay-title="聚焦右侧显示器 (vim)" { focus-monitor-right; }

    Mod+Shift+Ctrl+Left  hotkey-overlay-title="整列移到左显示器 Move column to monitor left" { move-column-to-monitor-left; }
    Mod+Shift+Ctrl+Down  hotkey-overlay-title="整列移到下显示器 Move column to monitor down" { move-column-to-monitor-down; }
    Mod+Shift+Ctrl+Up    hotkey-overlay-title="整列移到上显示器 Move column to monitor up" { move-column-to-monitor-up; }
    Mod+Shift+Ctrl+Right hotkey-overlay-title="整列移到右显示器 Move column to monitor right" { move-column-to-monitor-right; }

    Mod+Shift+Ctrl+H hotkey-overlay-title="整列移到左显示器 (vim)" { move-column-to-monitor-left; }
    Mod+Shift+Ctrl+J hotkey-overlay-title="整列移到下显示器 (vim)" { move-column-to-monitor-down; }
    Mod+Shift+Ctrl+K hotkey-overlay-title="整列移到上显示器 (vim)" { move-column-to-monitor-up; }
    Mod+Shift+Ctrl+L hotkey-overlay-title="整列移到右显示器 (vim)" { move-column-to-monitor-right; }

    // 整个工作区搬到另一台显示器
    Mod+Shift+Alt+W hotkey-overlay-title="工作区移到上显示器 Move workspace up" { move-workspace-to-monitor-up; }
    Mod+Shift+Alt+S hotkey-overlay-title="工作区移到下显示器 Move workspace down" { move-workspace-to-monitor-down; }
    Mod+Shift+Alt+D hotkey-overlay-title="工作区移到右显示器 Move workspace right" { move-workspace-to-monitor-right; }
    Mod+Shift+Alt+A hotkey-overlay-title="工作区移到左显示器 Move workspace left" { move-workspace-to-monitor-left; }

    // ========================================================================
    // 十五、工作区切换
    // ========================================================================

    Mod+Page_Down hotkey-overlay-title="切换到下一个工作区 Workspace down" { focus-workspace-down; }
    Mod+Page_Up   hotkey-overlay-title="切换到上一个工作区 Workspace up" { focus-workspace-up; }
    Mod+U hotkey-overlay-title="切换到下一个工作区 (u/i)" { focus-workspace-down; }
    Mod+I hotkey-overlay-title="切换到上一个工作区 (u/i)" { focus-workspace-up; }

    // 把当前列移到其它工作区
    Mod+Ctrl+Page_Down hotkey-overlay-title="把整列移到下一工作区" { move-column-to-workspace-down; }
    Mod+Ctrl+Page_Up   hotkey-overlay-title="把整列移到上一工作区" { move-column-to-workspace-up; }
    Mod+Ctrl+U hotkey-overlay-title="把整列移到下一工作区 (u/i)" { move-column-to-workspace-down; }
    Mod+Ctrl+I hotkey-overlay-title="把整列移到上一工作区 (u/i)" { move-column-to-workspace-up; }

    // 鼠标滚轮切换工作区
    Mod+Shift+WheelScrollDown hotkey-overlay-title="滚轮切换工作区 Change workspaces (down)" cooldown-ms=150 { focus-workspace-down; }
    Mod+Shift+WheelScrollUp   hotkey-overlay-title="滚轮切换工作区 Change workspaces (up)" cooldown-ms=150 { focus-workspace-up; }
    Mod+Ctrl+Shift+WheelScrollDown hotkey-overlay-title="滚轮把整列移到其它工作区 (down)" cooldown-ms=150 { move-column-to-workspace-down; }
    Mod+Ctrl+Shift+WheelScrollUp   hotkey-overlay-title="滚轮把整列移到其它工作区 (up)" cooldown-ms=150 { move-column-to-workspace-up; }

    // 鼠标滚轮左右切换聚焦
    Mod+WheelScrollDown hotkey-overlay-title="滚轮切换聚焦 Change focus with wheel (right)" { focus-column-right; }
    Mod+WheelScrollUp   hotkey-overlay-title="滚轮切换聚焦 Change focus with wheel (left)" { focus-column-left; }
    Mod+Ctrl+WheelScrollDown hotkey-overlay-title="滚轮左右移动整列 (right)" { move-column-right; }
    Mod+Ctrl+WheelScrollUp   hotkey-overlay-title="滚轮左右移动整列 (left)" { move-column-left; }

    // 数字键直接跳到第 N 个工作区
    Mod+1 hotkey-overlay-title="跳到工作区 1" { focus-workspace 1; }
    Mod+2 hotkey-overlay-title="跳到工作区 2" { focus-workspace 2; }
    Mod+3 hotkey-overlay-title="跳到工作区 3" { focus-workspace 3; }
    Mod+4 hotkey-overlay-title="跳到工作区 4" { focus-workspace 4; }
    Mod+5 hotkey-overlay-title="跳到工作区 5" { focus-workspace 5; }
    Mod+6 hotkey-overlay-title="跳到工作区 6" { focus-workspace 6; }
    Mod+7 hotkey-overlay-title="跳到工作区 7" { focus-workspace 7; }
    Mod+8 hotkey-overlay-title="跳到工作区 8" { focus-workspace 8; }
    Mod+9 hotkey-overlay-title="跳到工作区 9" { focus-workspace 9; }

    // Ctrl+数字：把当前列移到第 N 个工作区
    Mod+Ctrl+1 hotkey-overlay-title="把整列移到工作区 1" { move-column-to-workspace 1; }
    Mod+Ctrl+2 hotkey-overlay-title="把整列移到工作区 2" { move-column-to-workspace 2; }
    Mod+Ctrl+3 hotkey-overlay-title="把整列移到工作区 3" { move-column-to-workspace 3; }
    Mod+Ctrl+4 hotkey-overlay-title="把整列移到工作区 4" { move-column-to-workspace 4; }
    Mod+Ctrl+5 hotkey-overlay-title="把整列移到工作区 5" { move-column-to-workspace 5; }
    Mod+Ctrl+6 hotkey-overlay-title="把整列移到工作区 6" { move-column-to-workspace 6; }
    Mod+Ctrl+7 hotkey-overlay-title="把整列移到工作区 7" { move-column-to-workspace 7; }
    Mod+Ctrl+8 hotkey-overlay-title="把整列移到工作区 8" { move-column-to-workspace 8; }
    Mod+Ctrl+9 hotkey-overlay-title="把整列移到工作区 9" { move-column-to-workspace 9; }

    // ========================================================================
    // 十六、列内窗口操作
    // ========================================================================

    // 在相邻列之间移动单个窗口（不合并）
    Mod+BracketLeft  hotkey-overlay-title="窗口移到左列 Move window left" { consume-or-expel-window-left; }
    Mod+BracketRight hotkey-overlay-title="窗口移到右列 Move window right" { consume-or-expel-window-right; }
    Mod+A hotkey-overlay-title="窗口移到左列 (a/d)" { consume-or-expel-window-left; }
    Mod+D hotkey-overlay-title="窗口移到右列 (a/d)" { consume-or-expel-window-right; }

    // 同列内上下切换窗口
    Mod+W hotkey-overlay-title="切换到上方窗口 (s/w)" { focus-window-up; }
    Mod+S hotkey-overlay-title="切换到下方窗口 (s/w)" { focus-window-down; }
    Mod+Ctrl+S hotkey-overlay-title="窗口在列内下移 (s/w)" { move-window-down; }
    Mod+Ctrl+W hotkey-overlay-title="窗口在列内上移 (s/w)" { move-window-up; }

    // 合并两个窗口成一列（像标签页一样叠放）
    Mod+Comma hotkey-overlay-title="把窗口并入当前列 Consume into column" { consume-window-into-column; }
    // 把窗口从列里拆出来成为独立列
    Mod+Period hotkey-overlay-title="把窗口从列里拆出 Expel from column" { expel-window-from-column; }
    Mod+Shift+A hotkey-overlay-title="把窗口并入当前列 (shift+a/d)" { consume-window-into-column; }
    Mod+Shift+D hotkey-overlay-title="把窗口从列里拆出 (shift+a/d)" { expel-window-from-column; }

    // 当前列切换为标签页显示模式（多个窗口叠成标签）
    Mod+X hotkey-overlay-title="列切换标签页模式 Toggle tabbed display" { toggle-column-tabbed-display; }
    Mod+Shift+X hotkey-overlay-title="列切换标签页模式 (shift+x)" { toggle-column-tabbed-display; }

    // 鼠标侧键切换同列内的窗口
    Mod+MouseForward hotkey-overlay-title="鼠标侧键切上方窗口" { focus-window-up; }
    Mod+MouseBack    hotkey-overlay-title="鼠标侧键切下方窗口" { focus-window-down; }

    // ========================================================================
    // 十七、窗口尺寸
    // ========================================================================

    // 在预设宽度间循环（1/3 → 1/2 → 2/3 → 全宽）
    Mod+R hotkey-overlay-title="按预设切换宽度 Switch width" { switch-preset-column-width; }
    // 在预设高度间循环
    Mod+Shift+R hotkey-overlay-title="按预设切换高度 Switch height" { switch-preset-window-height; }
    // 重置窗口高度为自动
    Mod+Ctrl+R hotkey-overlay-title="重置窗口高度 Reset height" { reset-window-height; }

    // 最大化当前列（占满可用宽度）
    Mod+F hotkey-overlay-title="最大化 maximize" { maximize-column; }
    // 全屏当前窗口（隐藏状态栏等所有 UI）
    Mod+Alt+F hotkey-overlay-title="全屏 fullscreen" { fullscreen-window; }
    // 最小化当前窗口（收进状态栏）
    Mod+M hotkey-overlay-title="最小化 Minimize" { minimize-window; }

    // 扩展到可用宽度
    Mod+Ctrl+F hotkey-overlay-title="扩展到可用宽度 Expand to available width" { expand-column-to-available-width; }
    // 当前列居中
    Mod+C hotkey-overlay-title="当前列居中 Center column" { center-column; }
    // 所有可见列一起居中
    Mod+Ctrl+C hotkey-overlay-title="所有可见列居中 Center visible columns" { center-visible-columns; }

    // 微调整列宽度（每次 5%）
    Mod+Minus hotkey-overlay-title="列宽 -5%" { set-column-width "-5%"; }
    Mod+Equal hotkey-overlay-title="列宽 +5%" { set-column-width "+5%"; }

    // 微调窗口高度（每次 5%）
    Mod+Shift+Minus hotkey-overlay-title="窗口高 -5%" { set-window-height "-5%"; }
    Mod+Shift+Equal hotkey-overlay-title="窗口高 +5%" { set-window-height "+5%"; }

    // ========================================================================
    // 十八、浮动窗口
    // ========================================================================

    // 当前窗口在「平铺 / 浮动」之间切换
    Mod+V hotkey-overlay-title="切换浮动 Toggle floating" { toggle-window-floating; }
    // 在浮动窗口和平铺窗口之间切换焦点
    Mod+Shift+V hotkey-overlay-title="浮动/平铺间切换焦点" { switch-focus-between-floating-and-tiling; }
    Mod+N hotkey-overlay-title="浮动/平铺间切换焦点 (n)" { switch-focus-between-floating-and-tiling; }
    Alt+grave hotkey-overlay-title="浮动/平铺间切换焦点 (alt+`)" { switch-focus-between-floating-and-tiling; }
    Mod+Alt+N hotkey-overlay-title="浮动/平铺间切换焦点 (alt+n)" { switch-focus-between-floating-and-tiling; }

    // ========================================================================
    // 十九、杂项
    // ========================================================================

    // 临时把快捷键交给当前窗口（远程桌面/虚拟机里需要在宿主用组合键时）
    Mod+Escape allow-inhibiting=false hotkey-overlay-title="把快捷键交给当前窗口 Inhibit shortcuts" { toggle-keyboard-shortcuts-inhibit; }

    // 退出 niri（不是关机！只是退出桌面会话，回登录界面）
    Mod+Shift+E hotkey-overlay-title="退出niri Quit niri" { quit; }
}
NIRIEOF

    if chown -R "$REAL_USER:$REAL_USER" "$NIRI_CONF_DIR" 2>/dev/null; then
        log_info "  完整 niri 配置已写入: $NIRI_CONF"
    else
        log_warn "  配置已写入但 chown 失败，请手动修正:"
        log_warn "    sudo chown -R $REAL_USER:$REAL_USER $NIRI_CONF_DIR"
    fi
else
    log_warn "  无法创建 $NIRI_CONF_DIR，跳过 niri 配置"
    FAILED_STEPS+=("写入 niri 配置")
fi

# niri 配置语法自检
if command -v niri >/dev/null 2>&1 && [ -f "$NIRI_CONF" ]; then
    if niri validate -c "$NIRI_CONF" >/dev/null 2>&1; then
        log_info "  niri 配置语法校验通过。"
    else
        log_warn "  niri 配置语法校验未通过，请手动检查:"
        log_warn "    niri validate -c $NIRI_CONF"
        FAILED_STEPS+=("niri 配置语法校验")
    fi
fi

# ---------- 完成 ----------
echo ""
log_info "=========================================="
if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    log_info "全部配置完成！"
else
    log_warn "配置完成，但以下步骤失败："
    for step in "${FAILED_STEPS[@]}"; do
        log_warn "  失败: $step"
    done
    log_warn "请检查上面日志并手动处理。"
fi
log_info "=========================================="
log_info ""
log_info "建议重启系统以确保所有更改生效:"
log_info "  sudo systemctl reboot"
log_info ""
log_info "greetd 已配置并启用，重启后应直接进入 Noctalia Greeter 登录界面。"
log_info ""

# ---------- 前置阶段已就绪的东西 ----------
log_info "=========================================================="
log_info "首次登录后的状态（前置脚本已为你准备好）"
log_info "=========================================================="
log_info ""

# kitty
if [ -f "$TARGET_HOME/.config/kitty/kitty.conf" ]; then
    log_info "✅ 终端 kitty — 已安装并配置（透明 80%、无边框、光标拖尾）"
    if grep -q '^shell fish' "$TARGET_HOME/.config/kitty/kitty.conf" 2>/dev/null; then
        if command -v fish >/dev/null 2>&1; then
            log_info "    └─ shell: fish ✅"
        else
            log_info "    └─ shell: fish ⚠ 未安装，kitty 会回退默认 shell"
        fi
    fi
    if fc-list 2>/dev/null | grep -qi "JetBrains Maple Mono"; then
        log_info "    └─ 字体: JetBrains Maple Mono ✅"
    else
        log_info "    └─ 字体: ⚠ Maple Mono 未装上，将回退默认等宽字体"
    fi
    log_info "    └─ 配色: current-theme.conf ✅（Noctalia 运行后会按壁纸更新）"
else
    log_warn "⚠ kitty 配置未写入，请检查上面的步骤 12 日志"
fi
log_info ""

# niri 最小配置
if [ -f "$NIRI_CONF" ] && grep -q 'spawn-at-startup.*noctalia' "$NIRI_CONF"; then
    log_info "✅ niri 最小配置 — 已写入（含 Noctalia 自启）"
    log_info "    └─ 文件: $NIRI_CONF"
    log_info "    └─ 快捷键: Mod+T 终端 / Mod+Q 关窗 / Mod+O 总览 / Mod+1-3 工作区"
else
    log_warn "⚠ niri 配置未写入或未含 Noctalia 自启，请检查步骤 13"
fi
log_info ""
log_info "=========================================================="
log_info "重启后你能做什么"
log_info "=========================================================="
log_info "  1. Greeter 登录界面 → 选择 niri 会话 → 登录"
log_info "  2. 会看到 Noctalia 状态栏（顶部/底部）"
log_info "  3. Mod+T 打开 kitty 终端（已美化）"
log_info "  4. 用终端继续后续操作"
log_info ""
log_info "【可选】更完整的桌面配置（starship 提示符、yazi、eza、别名、"
log_info "        完整快捷键、matugen 主题联动等）:"
log_info "  git clone <fedora-niri-noctalia-config 仓库>"
log_info "  cd fedora-niri-noctalia-config && ./install.sh"
log_info ""
log_info "登录界面未出现时的排查命令（Ctrl+Alt+F3 切到 TTY）:"
log_info "  systemctl status greetd"
log_info "  journalctl -u greetd -b --no-pager | tail -50"
log_info "  cat /etc/greetd/config.toml"
log_info ""
log_info "验证 AMD 硬解: vainfo | grep -E 'VAProfileH264|VAProfileHEVC'"
log_info "验证 OpenGL: glxinfo | grep 'OpenGL renderer'"
