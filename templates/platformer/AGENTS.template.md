# AGENTS.md — {{title}}

> 本文件是**给 AI agent 的工作约定**，不是给用户看的说明。每次接手本项目先读它。
> 项目根：`{{root}}`
> 引擎：Defold 1.14.1 · macOS · 中文回复 · 一次只推进一项任务

---

## 0. 项目速览

| 项 | 值 |
|---|---|
| 入口 | `game.project` → `main.collectionc` |
| 常驻层 | `main.collection` 的 `loader` GO：`script/session.script` + `menu_proxy` + `game_proxy` |
| 按需场景 | `menu/menu.collection`、`game/game.collection` |
| 框架依赖 | `game.project` 的 `dependencies#0`（`fw-dist` 瘦包，只含 `framework/`），用 `require "framework.xxx"` |
| 唯一存档写入者 | `script/session.script`（子场景一律转发给它） |
| 跨集合通信 | `_G.{{PREFIX}}_SESSION = msg.url()`（依赖 `shared_state = 1`）+ 子场景发 `*_ready` 报到，session 用 **sender** 回包 |
| 配置前缀 | `{{prefix}}.`（`sys.get_config_string`） |
| app_id | `{{app_id}}` |
| 冒烟钩子 | `--config={{prefix}}.autotest=1`、`{{prefix}}.mock_death=1`、`{{prefix}}.smoke_ad=1` |
| 验证方式 | `build` → `run` → 日志/截图；必须真实重新编译，不能只查源码 |

**铁律**：不要手写 collection proxy 内部对象路径（`"proxy_id/obj#comp"` 在 bob 下解析不到）；
子场景 URL 一律用报到消息里的 `sender`。

---

## 1. 遇到难解决的问题：三步解决法

结论必须来自证据。禁止「实测引擎会丢弃」「框架不支持」这类没有日志/文档支撑的归因。

1. **查框架踩坑库**（随依赖分发，本项目里就有）：
   `find . -path "*framework/docs/README.md"`；本地开发时的源路径是
   `/Users/chendongming/coding/auto-games/defold/game-framework/framework/docs/README.md`。
   命中后按「防再犯检查清单」逐条核对；现象相同但结论不同，就在原文末尾追加「反例/补充」。
2. **查官方文档**（优先级高于论坛）：`https://defold.com/llms-manuals.txt`（手册全文）、
   `https://defold.com/llms-apis.txt`（API）、单篇 `https://defold.com/llms/manuals/<name>.md`。
   把**原文句子**摘出来再下结论，并记下 URL。优先看 "Caveats and common issues"。
3. **查论坛**：https://forum.defold.com —— 用「现象 + 组件名 + 引擎版本」搜。论坛用于佐证，
   不能推翻官方手册；冲突以手册 + 本地实测为准。

之后：先做最小实验证伪/证实根因 → 改代码 → 真实重新编译并跑一次 → 沉淀。

---

## 2. 沉淀规则（每解决一个难题必做）

写到框架仓库（单仓库、有 `.git`，不要在游戏仓库另起一份）：

```
/Users/chendongming/coding/auto-games/defold/game-framework/framework/docs/
```

- 文件名 `<YYYY-MM-DD>-<kebab-case-主题>.md`；同主题追加，不新建。
- 八段：现象与复现 / **错误假设（走过的弯路，别删）** / 三步查证结果（框架 docs → 官方 URL+原文 → 论坛 URL）/
  根因（带日志证据）/ 修复 / 验证（真实编译+运行）/ 防再犯检查清单 / 关联。
- 必须更新 `framework/docs/README.md` 导航表，否则等于没沉淀。
- 想让**本游戏**拿到，要 `publish-framework.py` 发新快照并改本仓库 `dependencies#0` 一行。
- 本项目的日常记录写 `.workbuddy/memory/<YYYY-MM-DD>.md`。

---

## 3. 常用命令

```bash
JAVA=/Applications/Defold.app/Contents/Resources/packages/jdk-25.0.4.1+1/bin/java
$JAVA -jar .tools/bob.jar --root . resolve
$JAVA -jar .tools/bob.jar --root . --output build/arm64-macos --platform arm64-macos \
      --variant debug --archive build
find build/arm64-macos/framework -name '*.luac' | wc -l    # 15 左右；0 说明依赖没解析到
```

- 编辑器：`Cmd+B` Build & Run。**旧实例不会自动加载新代码，改完必须重新 Build & Run。**
- `defold_hot_reload` 前必须先 build，否则会推旧 `.scriptc`。

---

## 4. 协作约定

- 中文回复，简短编号式；一次只推进一项，从第一项开始。
- 先给方案/评审，再改代码；范围紧凑，不做无关重构。
- 处理已有文件时**保留原件、另存副本**。
- 验证以**真实重新编译/预览**为准，不接受只凭源码检查的口头结论。
- 每完成一轮实质工作，在 `.workbuddy/memory/<YYYY-MM-DD>.md` 追加记录。
