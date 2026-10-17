# Luma

macOS 菜单栏亮度控制。**它只为一件事存在：睡一觉醒来，亮度还是你走之前那个亮度。**

自己用的工具，不发版、不上架。

## 为什么 MonitorControl 会「醒来失效」

在这台机器上（MacBook Pro M1 Pro + 内置屏 + U2790B + Redmi 27 NU）实测出来的链路：

| 显示器 | 系统原生调光 | 硬件 DDC | 实际用哪条 |
|---|---|---|---|
| 内置屏 | 可用 | 不适用 | DisplayServices（真背光） |
| Redmi 27 NU | 可用（读写一致） | 不可靠（读回永远 0） | DisplayServices（真背光） |
| U2790B (AOC) | 系统说不可改 | **不可用**（AOC 不回合法帧） | gamma 软件调光 |

关键结论：

1. **gamma 调光是按进程持有的**。哪个进程写了 gamma 表，它一退出（或者系统一睡），系统就把表还原成 1.0。
2. macOS 唤醒时会重置 gamma，但**不会重置 DisplayServices 的原生亮度**。所以内置屏和 Redmi 能自己扛过睡眠，只有走软件调光的 AOC 会「弹回最亮」。
3. MonitorControl 常驻，所以平时能用；但它唤醒后没有把值重写回去，于是 AOC 就亮回去了。它配置里 `forceSw(U2790B…)=true` 也印证了这块屏本来就只能软件调光。

实测对照（`pmset displaysleepnow` → `caffeinate -u`）：

```
没有 Luma：AOC gamma = 1.000   ← 回到最亮，bug 复现
启动 Luma：AOC gamma = 0.450   ← 4 秒内恢复
```

Luma 的做法：把「每块屏应该多亮」存下来，在 `screensDidWake` / `didWake` / 显示器热插拔时**按 1s / 1.5s / 3s / 5s 连写四遍**——只写一遍不够，系统自己在唤醒后一两秒里还会再覆盖一次。

## 安装

DMG 拖进「应用程序」即可。

- App 自带 Python 运行时和 PyObjC（38MB），**不需要联网、不需要装 Python**，Dock 里显示的是 Luma 而不是 Python。
- 要求：macOS 13+，Apple Silicon。
- 首次打开如果被 Gatekeeper 拦（从网上下载的 DMG 才可能发生）：右键 → 打开。

## 使用

打开 Luma 会出现一个窗口。它是菜单栏应用：**不占 Dock、不进 Cmd-Tab**，入口是菜单栏那个小太阳。

- 每块屏一行滑块，拖到你要的亮度，自动记住。
- 关掉窗口不退出，点菜单栏小太阳可以再打开。
- 菜单栏图标如果被 macOS 26 藏了，去「应用程序」里双击 Luma 也能把窗口叫出来。
- 「自启:关」点一下变成「自启:开」，登录后自动常驻。
- 「调光:自动 / 调光:软件」：默认自动（能原生就原生，否则软件调光）。
- 窗口右下角「退出」才是真的退出。

## 命令行

```bash
~/Applications/Luma.app/Contents/MacOS/Luma list          # 列出显示器和亮度
~/Applications/Luma.app/Contents/MacOS/Luma set 60 aoc    # 按名字/厂商/U2790B/redmi/builtin/all
~/Applications/Luma.app/Contents/MacOS/Luma nudge -5 all  # 在当前基础上加减
~/Applications/Luma.app/Contents/MacOS/Luma restore       # 恢复记录值
~/Applications/Luma.app/Contents/MacOS/Luma doctor        # 自检（含最近日志）
```

装的时候带 `--cli` 会在 `~/.local/bin/luma` 建一个软链。

注意：**命令行不直接写 gamma**。有常驻 App 时，命令行只改状态文件，由 App 去写——否则命令行进程一退出，就会把 App 持有的 gamma 一起冲掉（这个坑实测踩过）。App 没在跑时会直接写，并提示「不持久」。

## 代码结构

```
setup.py             # py2app 打包配置（把运行时塞进 Luma.app）
run_luma.py          # py2app 入口脚本
tools/make_icon.py   # 生成 App 图标
luma/cg.py           # ctypes 绑定：CoreGraphics（gamma）+ DisplayServices（原生亮度）
luma/displays.py     # 枚举、命名、稳定 key、控制方式选择
luma/controller.py   # 核心：应用亮度、唤醒恢复、状态轮询、日志
luma/store.py        # 状态持久化（~/Library/Application Support/Luma/state.json）
luma/app.py          # 菜单栏 UI
luma/cli.py          # 命令行
luma/login.py        # LaunchAgent 登录自启
```

构建（构建机需要一次联网装 py2app，产物本身不依赖网络）：

```bash
./build.sh          # 生成 dist/Luma.app
./install.sh        # 装到 /Applications（可加 --login --cli）
./make-dmg.sh       # 生成 dist/Luma-1.0.0.dmg
```

## 已知限制

- 只做亮度，没有音量和 OSD（用不上就不写）。
- AOC 走软件调光，所以降的是画面亮度而不是背光；这也是它原本在 MonitorControl 里的工作方式。
- 软件调光必须 Luma 常驻；把 App 退了 AOC 会回到最亮，这是系统的行为，不是 bug。
- 不要和 MonitorControl 同时运行，两边都会写亮度，会打架。

## 以后想加

- 音量 / 静音：加一个 DDC 后端（帧格式已经摸清：`[0x80|len+1, len] + data + checksum`，读回复从 offset 0 读 11 字节、0x50 基准校验），或走 CoreAudio。
- 全局快捷键：`RegisterEventHotKey`（不需要辅助功能权限）。
- 每屏独立的 gamma 曲线 / 最低亮度下限。
