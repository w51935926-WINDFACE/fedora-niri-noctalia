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

---

## 使用方法

```bash
sudo bash setup-niri-pre-v9.sh
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

## ⚠️ 重启后仍需手动做的一步

脚本跑完重启后，你会进入 Noctalia Greeter 登录界面，登进去是 **Niri 本体**。

**但 Noctalia Shell 不会自动启动** —— 需要在 Niri 配置里加一行。

编辑 `~/.config/niri/config.kdl`：

```kdl
// 让 Noctalia 随会话启动
spawn-at-startup "noctalia"

// 建议同时加上键位绑定，否则面板/启动器无法唤出
binds {
    Mod+Space { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+S     { spawn-sh "noctalia msg panel-toggle control-center"; }
    Mod+Comma { spawn-sh "noctalia msg settings-toggle"; }
}
```

> 首次运行 Niri 时它才会自动生成默认配置。如果文件还不存在，先启动一次 Niri。
>
> 完整配置（窗口圆角、模糊、壁纸策略等）见官方文档：
> https://docs.noctalia.dev/noctalia/compositor-settings/niri/

脚本末尾会检测这一步是否已完成并给出提示。

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
