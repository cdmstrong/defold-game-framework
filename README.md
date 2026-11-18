# Defold Game Framework

可复用的 Defold 游戏框架库。被各游戏仓库通过 `game.project` 的 `dependencies` 引用，实现「框架只维护一份、多游戏共享」的架构。

## 包含模块

- `framework/core/` — 应用生命周期（app）、事件总线（event_bus）、暂停管理（pause）
- `framework/ui/` — 屏幕管理（screen）、Monarch 导航适配器、可复用组件（button/progress_bar/currency_bar/item_card/confirm_dialog/toast/tab/scroll）、主题（theme）
- `framework/save/` — 存储（storage）、存档管理（save_manager，主备双槽+逐级迁移）、迁移（migration）
- `framework/services/` — 设置（settings）、音频（audio）
- `framework/data/` — 本地化（localization）
- `framework/platform/` — 平台检测、激励视频广告（reward_ad，taptap/233/mock/none provider）、广告日志
- `framework/analytics/` — 埋点（analytics）

## 如何被游戏仓库引用

在游戏仓库的 `game.project` 中声明：

```
dependencies#0 = <本库的 zip 归档 URL>
dependencies#1 = https://codeload.github.com/Insality/druid/zip/9a5171377fc2f7fba68fea4f2c117ee6a25d28a4
dependencies#2 = https://codeload.github.com/britzl/monarch/zip/5c33c39830489925493163e741d5b22b4e5e3b9d
dependencies#3 = https://codeload.github.com/Insality/defold-event/zip/384813497c25ff41d34ab1efdb1163217dc9dd26
```

然后 `Fetch Libraries`。库内模块通过 `require "framework.xxx"` 使用。

> 注意：框架依赖 druid / monarch / defold-event 三个第三方库。由于 Defold 的依赖是扁平解析的，游戏仓库需要在 `dependencies` 里同时列出这三个库（框架仓库声明依赖是为了框架自身可编译/测试）。

## 升级框架

框架仓库发新 tag / 新 zip 归档 → 游戏仓库改 `dependencies#0` 的 URL → `Fetch Libraries`。

## 纯 Lua 单测

`tests/lua/` 下是框架模块的纯 Lua 单测（不依赖 Defold 运行时），用 `lua tests/lua/test_xxx.lua` 运行。
