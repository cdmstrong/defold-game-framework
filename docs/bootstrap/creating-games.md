# 批量创建新游戏的操作手册

> **历史文档（2026-11-18 归档）**。本文的 `examples/<游戏名>/` 结构对应当时的 miner 模板，
> 仓库里的 `examples/` 已更名为 `templates/`（`miner/`、`ui-demo/`），新流程请用
> [`framework/docs/project-bootstrap.md`](../../framework/docs/project-bootstrap.md) 与
> `templates/platformer/` 的 proxy 骨架。本文保留是为了记住当时的目录约定与踩过的坑。

本文说明如何用 `defold-game-framework` 框架，批量创建独立游戏仓库。

## 仓库地址

- **框架仓库（公开）**：https://github.com/cdmstrong/defold-game-framework
- **演示游戏仓库（私有）**：https://github.com/cdmstrong/miner-game

框架仓库已设为公开，GitHub 的 codeload 归档 URL 可被 Defold 匿名拉取。

## 架构总览

```
defold-game-framework        ← 框架仓库（只维护这一份）
├── framework/               ← 33 个可复用模块
├── tests/lua/               ← 框架纯 Lua 单测
├── game.project             ← include_dirs = framework
└── git tag: v1.0.0, v1.1.0 ...

<每个新游戏一个独立仓库>        ← 游戏仓库（只放游戏逻辑）
├── game.project             ← dependencies 引用框架 + druid/monarch/event
├── examples/<游戏名>/       ← 游戏逻辑（bootstrap/context/view/game + 页面接线）
└── assets/                  ← 游戏专属资源（字体/图标/图片）
```

**核心原则**：框架只维护一份；游戏仓库通过 `dependencies` 引用框架，改框架 = 发新 tag + 游戏改一行 URL。

## 一、框架仓库（一次性，已建好）

位置：`/Users/chendongming/coding/auto-games/defold/defold-game-framework`

- 改框架模块 → `git commit` → 打新 tag（如 `v1.1.0`）→ 生成 zip 归档
- 框架依赖 druid / monarch / defold-event（在 `game.project` 的 dependencies 里声明，用于框架自身可编译/测试）

## 二、新建一个游戏仓库（每次照做）

### 1. 建目录 + 复制游戏模板

```bash
GAME=my-game
cd /Users/chendongming/coding/auto-games/defold
mkdir -p $GAME/examples/$GAME $GAME/assets/fonts
# 以 miner 为模板复制游戏逻辑（或从零写）
cp -R miner-game/examples/miner/* $GAME/examples/$GAME/
cp -R miner-game/assets/fonts/* $GAME/assets/fonts/
```

### 2. 写 game.project

```ini
[project]
title = My Game
version = 1.0.0
dependencies#0 = <框架 zip URL>
dependencies#1 = <druid zip URL>
dependencies#2 = <monarch zip URL>
dependencies#3 = <event zip URL>

[bootstrap]
main_collection = /examples/my-game/main.collectionc

[input]
game_binding = /builtins/input/all.input_bindingc

[display]
width = 960
height = 640
update_frequency = 60

[script]
shared_state = 1

[html5]
scale_mode = fit

[druid]
no_auto_input = 0
```

依赖 URL 两种写法：

- **正式（GitHub，推荐）**：`https://codeload.github.com/cdmstrong/defold-game-framework/zip/<commit-sha>`（codeload 格式，和 druid/monarch 一致）
- **本地开发（离线可复现）**：`http://127.0.0.1:8899/fw.zip`（需本地起 HTTP 服务提供 zip）

> 注意：
> - druid/monarch/event 也必须列出，因为 Defold 依赖是扁平解析的，游戏仓库要自己声明全部第三方依赖。
> - GitHub 的 `github.com/.../archive/...` 链接在本机网络下连接会被重置，请用 `codeload.github.com/.../zip/<sha>` 格式。
> - Bob 并发下载多个 codeload 归档时在本机网络下偶发中断（4 个依赖随机某个失败）。若 resolve 报 `Failed to fetch`，可重试，或改用本地 HTTP 方式一次性 resolve（见下文「本地提供框架 zip」）。

### 3. 复制构建工具链

```bash
mkdir -p .tools .internal/lib
cp ../defold-game-framework/.tools/bob.jar .tools/   # 或复用任意项目的 bob.jar
```

### 4. resolve + build 验证

```bash
JAVA=/Applications/Defold.app/Contents/Resources/packages/jdk-25.0.4.1+1/bin/java
$JAVA -jar .tools/bob.jar --root . resolve
$JAVA -jar .tools/bob.jar --root . --output build/wasm-web --platform wasm-web --variant debug --archive build
```

验证要点：build 产物里应出现 `framework/` 和 `monarch/` 的 `.luac`（说明框架模块已从依赖正确解析）。

### 5. git 管理

```bash
git init && git add -A && git commit -m "feat: <游戏名> v0.1.0"
```

## 三、升级框架（框架改了之后）

1. 在框架仓库提交 + 打新 tag `v1.1.0` + 生成 `v1.1.0.zip`
2. 游戏仓库改 `game.project` 的 `dependencies#0` URL 为新 tag
3. `resolve` + `build` 验证

## 四、本地提供框架 zip（离线流程）

框架仓库发 tag 后生成 zip，用本地 HTTP 服务提供：

```bash
# 1. 生成 zip（在框架仓库）
cd defold-game-framework
zip -r ../framework-releases/v1.1.0.zip framework game.project README.md LICENSE tests .gitignore

# 2. 起本地服务（后台常驻）
cd ../framework-releases
python3 -m http.server 8899 --bind 127.0.0.1

# 3. 游戏 game.project 里写
# dependencies#0 = http://127.0.0.1:8899/v1.1.0.zip
```

## 五、常见坑

1. **GitHub codeload 下载不稳定**：druid/monarch/event 若下载中断，可从任意已缓存的项目的 `.internal/lib/` 复制对应 zip 到本地 HTTP 服务目录，用本地 URL 引用。
2. **bundle 需要连 Defold 官方 extender 服务器**：`bundle` 阶段会联网构建 wasm/原生引擎；纯验证 `require` 用 `build`（非 bundle）即可。
3. **本地 HTTP 服务要用 `run_in_background` 方式启动**：用 `&` 启动会随命令结束被回收，导致依赖下载失败。
4. **`framework/` 必须无 assets 耦合**：框架只放 `.lua`，不引用游戏专属的图片/字体；游戏专属资源放游戏仓库的 `assets/`。
