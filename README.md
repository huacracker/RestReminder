# 休息提醒 RestReminder

macOS 菜单栏小工具：**工作满 1 小时，全屏遮盖提醒你休息 5 分钟**（带倒计时），可一键关闭，也可最小化到角落继续倒计时。

原生 Swift + AppKit，无依赖、无网络、不收集任何数据。

## 功能

- **计时**：默认工作 60 分钟 → 休息 5 分钟，循环。菜单栏实时显示「距离下次休息 42m」/ 休息中「4:32」。
- **全屏遮盖**：休息开始时盖住**所有屏幕**（主屏显示大字倒计时 + 进度环 + 「我休息好了 / 最小化」按钮，副屏只显示倒计时）。
- **倒计时**：5 分钟走完自动关闭，回到工作计时；休息期间禁止显示器休眠。
- **手动关闭**：点「我休息好了」，或按 `ESC`；也可在菜单里点「结束这次休息」。
- **最小化**：点「最小化」或按 `空格` → 全屏遮盖收起，右下角留一个小悬浮条「☕️ 休息 4:32」，**点击即还原**全屏。悬浮条可拖动。
- **提醒**：提示音 + 系统通知（可选语音叮嘱，用 `say` 念「该休息了，站起来走动走动，看看远处」）。
- **菜单**：工作间隔 15/25/30/45/50/60/90/120 分钟、休息时长 3/5/10/15 分钟、遮盖所有屏幕、提示音、语音叮嘱、开机自动启动、暂停计时、重新开始这一轮、立即休息。
- **开机自启**：菜单勾选即可（写入 `~/Library/LaunchAgents/com.huage.restreminder.plist`）。

> 不需要任何系统权限（无辅助功能/录屏/网络）。

## 安装

```bash
cd /Volumes/HuageAi-Code/Github/rest-reminder
./build.sh
```

编译 → 生成图标 → 签名 → 安装到 `~/Applications/休息提醒.app`（脚本会自动杀掉旧进程）。然后双击启动，菜单栏出现咖啡杯图标（无 Dock 图标）。

启动命令：`open -a ~/Applications/休息提醒.app`

## 快捷键

| 操作 | 键 |
|---|---|
| 结束休息 | `ESC` 或回车/按钮「我休息好了」 |
| 最小化到角落 | `空格` 或按钮「最小化」 |
| 还原全屏遮盖 | 点击右下角悬浮条 |

## 调试参数

命令行参数会覆盖设置（`NSArgumentDomain`，不写入配置）：

```bash
# 自检：立刻弹一次遮盖 → 最小化 → 还原 → 结束，打印诊断后退出 0
~/Applications/休息提醒.app/Contents/MacOS/RestReminder -selftest 1

# 快速跑一轮：工作 6 秒、休息 12 秒
~/Applications/休息提醒.app/Contents/MacOS/RestReminder -workMinutes 0.1 -breakMinutes 0.2
```

## 文件结构

```
Sources/main.swift        全部逻辑（菜单栏 / 计时状态机 / 遮盖窗口 / 悬浮条 / 自启）
scripts/gen-icon.swift    用 SF Symbol 生成 App 图标 iconset
build.sh                  编译 + 打包 + 签名 + 安装
assets/icon-512.png       图标预览
```

## 实现要点

- 遮盖窗口用 `NSWindow` level = `screenSaverWindow` + `canJoinAllSpaces`，borderless 且 `canBecomeKey = true`（否则 ESC/空格收不到）。
- 计时以 `deadline` 时间戳为准（不是累加 tick），合盖/休眠唤醒后时间仍准确。
- 悬浮条用 `NSPanel`（`.nonactivatingPanel`），显示/更新时不抢键盘焦点。
- 通知仅在 bundle 内调用 `UNUserNotificationCenter`（脱离 bundle 直接跑二进制会崩）。
