# Fedora 44 最小安装 → Niri + Noctalia v5 一键配置

在 **Fedora 44 最小安装（minimal install）** 的裸机上，一路配到「重启即可进入图形登录界面」。

适用场景：TTY 里跑完，重启就是 Niri 桌面 + Noctalia v5 外壳 + Noctalia Greeter 登录界面。

---

## 这个脚本做什么

| 步骤 | 内容 |
|---|---|
| 1 | 安装 `dnf-plugins-core` |
| 2 | 配置 DNF `fastestmirror` |
| 3 | 添加 RPM Fusion（free + nonfree） |
| 4 | 检查 RPM Fusion `tainted` 子仓库 |
| 5 | 系统完整更新（含内核变更重启提示） |
| 6 | AMD 显卡驱动与 VA-API 硬解（`mesa-va-drivers-freeworld`） |
| 7 | 完善视频编解码器（GStreamer / ffmpeg / libavcodec） |
| 8 | 安装 `niri` 与 `noctalia`（v5） |
| 9 | 添加 Terra 仓库（供 Greeter 使用） |
| 10 | 安装 `greetd` 与 `noctalia-greeter` |
| 11 | 配置 greetd 会话并启用服务 |
| 12 | 安装 `kitty` + `fish` + JetBrains Maple Mono 字体，写入美化配置 |
| 13 | 写入最小 niri 配置（自启 Noctalia、终端绑 kitty） |

> 第 12、13 步的目的：让**首次登录就能用**。
> 若不写这两步，niri 会使用内置默认配置 —— 不自启 Noctalia（没有状态栏、
> 壁纸、启动器），且默认终端绑的是 `alacritty`（本脚本装的是 `kitty`），
> 结果是一个「黑屏且打不开任何程序」的桌面。

---

## 使用方法

```bash
sudo bash setup-niri-pre-v10.sh
```

**必须以 root 运行**（脚本会自行检查，非 root 直接退出）。

脚本是幂等的：`greetd` 配置会**合并**而不是覆盖已有 `/etc/greetd/config.toml`，
重复运行不会破坏你手工改过的配置。

---

## 前置要求

- **Fedora 44** 最小安装（脚本会检测版本，< 44 会警告）
- 有网络连接
- **AMD 显卡**（NVIDIA / Intel 用户需自行调整第 6 步）
- 一个非 root 用户（脚本通过 `SUDO_USER` 识别目标用户）

---

## 重启后你会看到什么

脚本跑完 `sudo systemctl reboot`，重启后：

1. **Noctalia Greeter 登录界面** —— 选择 `niri` 会话，输入密码登录
2. **登录后即可用的桌面**：
   - Noctalia 状态栏（脚本写入的 niri 配置自启了 Noctalia）
   - `Mod+T` 打开 **kitty 终端**（已美化：80% 透明、无边框、光标拖尾）
   - `Mod+Q` 关窗 / `Mod+O` 总览 / `Mod+1`~`3` 切工作区 / `Mod+Shift+E` 退出

也就是说，**登录进去就是能用的**，不需要先进 TTY 补救。

### 前置脚本写入的配置文件

| 文件 | 内容 |
|---|---|
| `~/.config/kitty/kitty.conf` | kitty 美化配置（外观 + `shell fish` + 主题引用） |
| `~/.config/kitty/current-theme.conf` | 初始配色（Noctalia 运行后会按壁纸更新） |
| `~/.config/fish/config.fish` | fish 基础配置（完整配置由桌面配置脚本提供） |
| `~/.config/niri/config.kdl` | niri 最小配置（Noctalia 自启 + 基础快捷键） |

> 这些是**最小可用集**。更完整的桌面体验（starship 提示符、yazi、eza、
> 完整快捷键、matugen 主题联动等）由配套的配置仓库提供，会覆盖这些文件。

### 若某一步降级了

脚本末尾会逐项报告状态。常见降级情况：

| 现象 | 原因 | 处理 |
|---|---|---|
| 字体回退成默认等宽 | 字体下载失败（网络/GitHub API） | 手动下载安装后 `fc-cache -fv` |
| kitty 进去是 `sh`/`bash` 而非 fish | fish 安装失败 | `sudo dnf install fish` |
| 没有状态栏 | niri 配置未写入 | 检查脚本步骤 13 日志 |

---

## 排障

### 登录界面没出来

切到 TTY（`Ctrl+Alt+F3`）执行：

```bash
systemctl status greetd
journalctl -u greetd -b --no-pager | tail -50
cat /etc/greetd/config.toml
```

### 验证 AMD 硬解

```bash
vainfo | grep -E 'VAProfileH264|VAProfileHEVC'
```

### 验证 OpenGL

```bash
glxinfo | grep 'OpenGL renderer'
```

---

## 关于本脚本的几个设计决定

### 为什么不禁用旧显示管理器？

官方 Greeter 文档的 "Replace the current display manager safely" 一节，
前提是**系统已有 gdm/sddm/lightdm**。

最小安装的裸机没有 `display-manager`，直接 `systemctl enable greetd` 即可。
多写一步 `disable` 反而要额外处理「unit 不存在」的报错。

### 为什么 `noctalia` 和 `noctalia-greeter` 来源不同？

官方文档明确：

- **`noctalia`（v5 外壳）** —— Fedora 44+ **默认仓库**
  > "Noctalia is available from the default repos for Fedora 44 and up."
- **`noctalia-greeter`** —— 社区维护的 **Terra** 仓库
  > "Fedora's default repositories do not currently carry Noctalia Greeter."

### Noctalia v4 和 v5 是两套独立软件

> "Noctalia v5 is a fresh install, not an automatic upgrade from the
> Quickshell-based v4 implementation. Its package and configuration files
> are separate... v4 settings are not migrated."

Terra 仓库里 `noctalia-legacy` 才是 v4。本脚本只处理 v5。

### Terra 仓库的两种写法都保留

官方命令是：

```bash
sudo dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
```

单引号让 `$releasever` 交给 dnf 展开。有资料称 dnf5 的 `--repofrompath`
不再做该替换，**但此说法未经权威确认**。

脚本保留官方写法，同时加了 shell 展开的兜底分支 —— 两者任一成功即可。

### greetd 配置的两个坑（已规避）

1. **不能用全局 `sed` 改 `command`** —— 会把 `[initial_session]` 等段的
   `command` 一起改掉。脚本用 `awk` 限定 `[default_session]` 段内替换。

2. **段判定正则不能过严** —— `[ default_session ]`（段名两侧有空格）是
   合法 TOML。若用 `^\[default_session\]` 判定会漏掉，导致追加出**重复段**，
   而 TOML 重复表会解析失败（`Cannot declare ('default_session',) twice`），
   **greetd 直接拒绝启动**。脚本用
   `^[[:space:]]*\[[[:space:]]*default_session[[:space:]]*\]` 并加重复段检测。

---

## 已验证内容

- **bash 语法检查**：`bash -n` 通过
- **greetd 配置逻辑**：10 个沙箱场景实跑，全部通过

  段写法变体：`[ default_session ]` 两侧空格 / 行首缩进 / TAB 缩进 /
  空段头 —— 均正确识别为已有段，不产生重复

  常规场景：空文件 / 文件不存在 / 含 `[initial_session]` / 段内缺 `user`
  —— 均正确写入且不破坏其它段

  防护线：预置重复段文件能触发告警

- **Terra 包版本**（从 `terra44` 元数据核实）：
  `noctalia 5.0.0~beta.9` / `noctalia-greeter 1.5.0` /
  `noctalia-legacy 4.7.7`（=v4）/ `terra-release 0:44-9`

**未验证**（需要真实硬件）：

- Noctalia v5 在 AMD 机器上能否正常启动
- `noctalia-greeter` 实际登录界面表现

---

## 参考

- Noctalia 安装文档：https://docs.noctalia.dev/noctalia/getting-started/installation/
- Noctalia Greeter 安装文档：https://docs.noctalia.dev/greeter/installation/
- Noctalia Niri 集成：https://docs.noctalia.dev/noctalia/compositor-settings/niri/
- Terra 仓库：https://repos.fyralabs.com/
- RPM Fusion：https://rpmfusion.org/

---

## License

MIT
