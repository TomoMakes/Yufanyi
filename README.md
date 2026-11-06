<div align="center">

<img src="guide/icon.png" alt="预翻译 for Mac" width="128" height="128">

# 预翻译 for Mac

**在 Mac 上为视觉小说显示预翻译字幕**

框选游戏的对话区域，软件实时识别画面中的日文台词，并从 LunaTranslator 预翻译库中查找译文，以字幕形式显示。

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

[下载最新版本](https://github.com/TomoMakes/Yufanyi/releases) · [使用说明](guide/使用说明.txt)

</div>

---

## 简介

LunaTranslator 的预翻译库收录了许多视觉小说的整句译文，但 LunaTranslator 只能在 Windows 上运行。本项目让 Mac 用户也能使用这些预翻译库：

- 通过屏幕文字识别（OCR）读取框选区域内的台词，无需针对单个游戏编写读取程序；
- 在预翻译库中查找对应译文，查不到时显示原文，不会用机器翻译替代；
- 全程在本机运行，不上传截图或文字。

目前为免费测试版，仅支持日文原文。

## 系统要求

- macOS 15 或更高版本，Apple 芯片与 Intel 芯片均可使用
- 与游戏对应的 LunaTranslator 预翻译库（`.sqlite`），需自行准备。本项目不提供、不托管任何预翻译数据。

## 安装与使用

1. 在 [Releases](https://github.com/TomoMakes/Yufanyi/releases) 下载 DMG，将「预翻译 for Mac.app」拖入「应用程序」。
2. 本软件暂未进行 Apple 付费签名。首次打开如被系统拦截，请前往「系统设置 → 隐私与安全性」，点击「仍要打开」。
3. 按提示授予「录屏与系统录音」权限，然后重新打开软件。
4. 在设置的「高级」页面载入预翻译库，再从菜单栏选择「实时翻译」，框选游戏中的台词区域。

框选时只框台词区域，不要框入角色名字框。完整步骤见 [使用说明](guide/使用说明.txt)。

> 每次更新版本后，请在「录屏与系统录音」中移除旧条目，为新版本重新授权。

## 与原项目的区别

本项目基于 [ScreenTranslate](https://github.com/hcmhcs/screenTranslate)（作者 hanchangmin）修改，主要改动：

- 新增 LunaTranslator 预翻译库（`.sqlite`）匹配，包括按段落和台词拆分匹配、OCR 候选读法回收、同行拼接等，并在多条记录冲突时判为未命中，避免显示错误译文；
- 实时字幕改为本项目的主要功能，保留实时翻译、字幕字号与快捷键设置；
- 移除截图弹窗翻译、拖选翻译、快速翻译、翻译历史、在线翻译引擎和自动更新等与预翻译场景无关的功能；
- 关闭原版内置的使用统计（TelemetryDeck），本软件不收集任何使用数据；
- 界面改为简体中文，应用名称、图标与包标识均已更换，可与原版共存。

逐项修改可通过本仓库的提交记录查看。

## 从源码构建

需要较新版本的 Xcode（已在 Xcode 27 上验证）。

```bash
scripts/build-release.sh 0.1.0-beta
```

生成的 DMG 位于 `build/` 目录。

## 许可证

本项目依照 [GNU General Public License v3.0](LICENSE) 发布。

- 原项目 ScreenTranslate © 2026 hanchangmin，以 GPLv3 发布。原项目说明保留在 [README.upstream.md](README.upstream.md)。
- 修改部分 © 2026 TomoMakes。

## 致谢

感谢 ScreenTranslate 原作者 hanchangmin，感谢 LunaTranslator 项目，也感谢每一位制作和分享预翻译库的作者。
