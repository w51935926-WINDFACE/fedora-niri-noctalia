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
log_info "步骤 1/13: 安装 dnf-plugins-core..."
install_step "安装 dnf-plugins-core" dnf install -y dnf-plugins-core

# ---------- 2. 配置 fastestmirror ----------
log_info "步骤 2/13: 配置 DNF fastestmirror..."
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
log_info "步骤 3/13: 添加 RPM Fusion 仓库 (free + nonfree)..."
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
log_info "步骤 4/13: 检查 RPM Fusion tainted 子仓库..."

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
log_info "步骤 5/13: 执行系统完整更新..."
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
log_info "步骤 6/13: 检查并安装 AMD 显卡驱动组件..."
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
log_info "步骤 7/13: 完善视频编解码器..."

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
log_info "步骤 8/13: 安装 niri 与 Noctalia v5..."

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
log_info "步骤 9/13: 添加 Terra 仓库 (为 Noctalia Greeter)..."

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
log_info "步骤 10/13: 安装 Noctalia Greeter..."
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
log_info "步骤 11/13: 配置 greetd 会话..."

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
log_info "步骤 12/13: 安装 kitty + fish + 字体..."

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

# ---------- 13. 写入最小 niri 配置 ----------
# 为什么要写？
#   不写的话 niri 用内置默认配置:
#     - 不会自启 Noctalia  -> 没有状态栏、没有壁纸、没有启动器
#     - 默认终端绑 alacritty(未装) -> 开不了终端
#   写一个最小配置，让首次登录就能看到 Noctalia 界面并打开终端。
#
# 与完整配置的关系: 这是最小可用集，仅覆盖「能开机用」所需的部分。
#   更完整的桌面配置(starship/yazi/完整快捷键/matugen 联动)可另行部署。
log_info "步骤 13/13: 写入最小 niri 配置..."
NIRI_CONF_DIR="$TARGET_HOME/.config/niri"
NIRI_CONF="$NIRI_CONF_DIR/config.kdl"

if [ -d "$NIRI_CONF_DIR" ] && [ -f "$NIRI_CONF" ]; then
    log_info "  niri 配置已存在，保留不动: $NIRI_CONF"
    log_info "  （如需应用最小配置，请先备份再删除该文件）"
else
    if mkdir -p "$NIRI_CONF_DIR"; then
        cat > "$NIRI_CONF" <<'NIRIEOF'
// ============================================================================
// niri 最小配置 — 前置阶段版本
//
// 目的：让首次登录就能用（Noctalia 起来 + 终端能开）。
// 完整的桌面配置由 fedora-niri-noctalia-config 覆盖本文件。
//
// 若不写这份配置，niri 会用内置默认值：
//   - 不自启 Noctalia（无状态栏/壁纸/启动器）
//   - 终端默认绑 alacritty（本前置脚本装的是 kitty）
// ============================================================================

// 自启 Noctalia v5（提供状态栏、通知、壁纸、启动器、截图等）
spawn-at-startup "noctalia"

// 输入法环境（fcitx5 若已装则生效）
environment {
    XMODIFIERS "@im=fcitx"
    QT_IM_MODULE "fcitx"
    SDL_IM_MODULE "fcitx"
}

// 最小快捷键：保证能开终端、关窗口、切工作区
binds {
    // 终端（默认配置绑的是 alacritty，这里改成 kitty）
    Mod+T { spawn "kitty"; }

    // 关闭窗口
    Mod+Q { close-window; }

    // 总览
    Mod+O { toggle-overview; }

    // 窗口间切换聚焦
    Mod+Left  { focus-column-left; }
    Mod+Down  { focus-window-down; }
    Mod+Up    { focus-window-up; }
    Mod+Right { focus-column-right; }

    // 工作区
    Mod+U { focus-workspace-down; }
    Mod+I { focus-workspace-up; }
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }

    // 退出 niri
    Mod+Shift+E { quit; }
}
NIRIEOF

        if chown -R "$REAL_USER:$REAL_USER" "$NIRI_CONF_DIR" 2>/dev/null; then
            log_info "  最小 niri 配置已写入: $NIRI_CONF"
        else
            log_warn "  niri 配置已写入但 chown 失败，请手动修正:"
            log_warn "    sudo chown -R $REAL_USER:$REAL_USER $NIRI_CONF_DIR"
        fi
    else
        log_warn "  无法创建 $NIRI_CONF_DIR，跳过 niri 配置"
        FAILED_STEPS+=("写入 niri 配置")
    fi
fi

# niri 配置语法自检
if command -v niri >/dev/null 2>&1 && [ -f "$NIRI_CONF" ]; then
    if niri validate -c "$NIRI_CONF" >/dev/null 2>&1; then
        log_info "  niri 配置语法校验通过。"
    else
        log_warn "  niri 配置语法校验未通过，请手动检查: niri validate -c $NIRI_CONF"
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
