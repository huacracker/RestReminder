# 休息提醒 RestReminder

[English →](README.md) · [**完整中文使用说明 →**](docs/使用说明.md)

macOS 菜单栏小工具：工作满 **1 小时**，用**全屏遮盖 + 倒计时**叮嘱你休息 **5 分钟**；可以一键结束，也可以最小化到角落继续倒计时。

原生 Swift + AppKit，约 900 行，**无第三方依赖、不联网、不收集数据**，不申请任何系统权限。

![全屏休息提醒](docs/cover.png)

<p>
<img src="docs/icon.png" alt="图标" width="112">
<img src="docs/mini.png" alt="最小化后的倒计时条" width="224">
</p>

## 功能

- **工作 / 休息循环**：默认工作 60 分钟 → 休息 5 分钟，循环往复。菜单里可改（工作 15/25/30/45/50/60/90/120 分钟，休息 3/5/10/15 分钟）。菜单栏实时显示「距离下次休息 42m」或休息中「4:32」。
- **所有屏幕全屏遮盖**：休息开始时每块屏幕各盖一层（主屏显示大字倒计时环 + 按钮，副屏显示细长倒计时）。
- **倒计时归零自动关闭**：自动回到工作计时。休息期间禁止显示器休眠，不会因为你走开而错过。
- **手动关闭**：点「我休息好了」，或按 `ESC` / 回车。
- **最小化**：点「最小化」或按 `空格` → 全屏遮盖收起，右下角留下一个可拖动的小条「☕️ 休息 4:32」，继续倒计时，**点它即还原全屏**。小条是非激活窗口，你在打字时它不会抢走键盘焦点。
- **提醒方式**：系统提示音 + 通知，可选语音叮嘱（用 `say` 念「该休息了，站起来走动走动，看看远处」）。
- **开机自动启动**：菜单里一个勾选框（写入 `~/Library/LaunchAgents/com.restreminder.app.plist`）。

界面语言跟随系统：中文系统显示中文，其他显示英文。

## 安装

### 方式一：下载现成的 App

到 [Releases](../../releases) 下载 `RestReminder-1.0.0-macos-universal.dmg`（或 `.zip`），把 App 拖进 `Applications` 打开即可。

> **首次打开可能被 Gatekeeper 拦下。** 本 App 使用 ad-hoc 签名、**未做 Apple 公证**（公证需要付费开发者账号），macOS 可能提示「无法验证开发者」或「已损坏」。任选一种解除：
> - 右键点图标 →「打开」→ 再点「打开」；
> - 或执行一次：`xattr -dr com.apple.quarantine /Applications/RestReminder.app`
>
> 应用全程本地运行，不会下载任何东西，也不会外传数据。

### 方式二：从源码构建

只需要 macOS 命令行工具（`xcode-select --install`），**不需要完整 Xcode**。

```bash
git clone <本仓库>
cd RestReminder
./build.sh          # 编译本机架构 → 签名 → 安装到 ~/Applications
./build.sh run      # 顺便启动
```

打包通用二进制 + dmg + zip（发布版就是这么来的）：

```bash
./build.sh release  # dist/RestReminder-1.0.0-macos-universal.{dmg,zip}
```

## 使用

启动后**没有 Dock 图标**——去菜单栏找 ☕️，旁边显示距离下次休息的剩余时间。

| 操作 | 方式 |
|---|---|
| 提前结束休息 | 点「我休息好了」，或按 `ESC` / 回车 |
| 最小化遮盖 | 点「最小化」，或按 `空格` |
| 还原全屏遮盖 | 点右下角的小条 |
| 立刻休息一次 | 菜单 →「现在就去休息」 |
| 暂停 / 继续计时 | 菜单 →「暂停计时」 |
| 改间隔 | 菜单 →「工作间隔」/「休息时长」 |
| 只盖当前屏幕 | 菜单 → 取消勾选「遮盖所有屏幕」 |
| 开机自启 | 菜单 →「开机自动启动」 |

设置保存在 `~/Library/Preferences/com.restreminder.app.plist`。

## 调试 / 自检

App 可以自己驱动 UI，不用等一小时才能验证：

```bash
BIN=~/Applications/RestReminder.app/Contents/MacOS/RestReminder

# 走一遍完整流程（遮盖 → 最小化 → 还原 → 结束）并打印诊断，退出码 0
"$BIN" -selftest 1

# 真实跑一轮 6 秒工作 / 12 秒休息（命令行参数覆盖设置，不写入配置）
"$BIN" -workMinutes 0.1 -breakMinutes 0.2

# 把遮盖界面 / 最小化小条渲染成 PNG（不需要屏幕录制权限）
"$BIN" -snapshot /tmp/cover.png
"$BIN" -snapshot /tmp/mini.png -snapshotMini 1
```

## 实现要点

- 遮盖窗用 borderless `NSWindow`，层级 `CGWindowLevelForKey(.screenSaverWindow)` + `.canJoinAllSpaces`，所以能盖住全屏应用、所有 Space 和每一块屏幕；必须重写 `canBecomeKey = true`，否则 borderless 窗口收不到 `ESC` / `空格`。
- 最小化小条用 `NSPanel`（`.nonactivatingPanel`），显示和刷新都不会抢键盘焦点。
- 计时以 `deadline` 时间戳推算，而不是累加 tick，合盖休眠后时间不会漂。
- `-snapshot` 用 `cacheDisplay(in:to:)` 把视图树渲染成位图，而不是屏幕截图，所以整个功能不需要任何权限。

## 文件结构

```
Sources/main.swift        全部逻辑（菜单栏 / 计时状态机 / 遮盖窗 / 悬浮条 / 开机自启 / 多语言）
scripts/gen-icon.swift    生成 App 图标（SF Symbol → iconset → icns）
build.sh                  编译 / release（通用二进制 + dmg + zip）/ 运行
docs/                     README 用截图
```

## 许可

[MIT](LICENSE) © 2026 Huage
