# 新项目初始化 & 复制启动 SOP（通用模板）

> 这是**跨项目通用模板**，不含任何游戏专属值；具体实例见
> `/Users/chendongming/coding/auto-games/defold/platformer-game/AGENTS.md` 第 3 节。
> 仓库内的骨架在 `templates/`（`platformer/` 完整项目骨架、`miner/` 片段式参考），
> 每个模板带一份 `template.json` 声明骨架类型与需要改写的标识。
> 旧的《批量创建新游戏手册》已移到
> `/Users/chendongming/coding/auto-games/defold/defold-game-framework/docs/bootstrap/creating-games.md`
> （以 miner-game / `examples/<游戏名>/` 为历史结构，`examples/` 现已更名 `templates/`），
> 本 SOP 针对 `main.collection + collection proxy` 骨架。

## 0. 复用原则

框架只维护一份：`game-framework` 仓库；每个游戏一个独立仓库，通过 `game.project` 的
`dependencies` 以**不可变 commit ZIP** 引用。改框架 = 发新 tag + 游戏改一行 URL。

## 1. 复制骨架

```bash
BASE=/Users/chendongming/coding/auto-games/defold
SRC=$BASE/<模板项目>
GAME=<新项目目录名>
DST=$BASE/$GAME

rsync -a --exclude '.git/' --exclude 'build/' --exclude 'dist/' \
      --exclude '.internal/' --exclude '.tools/' --exclude 'logs/' --exclude '.workbuddy/' \
      --exclude '.editor_settings' --exclude 'screenshot.png' \
      "$SRC/" "$DST/"
cd "$DST"
mkdir -p .tools
cp "$BASE/game-framework/.tools/bob.jar" .tools/ 2>/dev/null || cp "$SRC/.tools/bob.jar" .tools/
```

必须排除本地产物：`build/`、`dist/`、`.internal/`、`logs/`、`.git/`、`.workbuddy/`、
`.tools/`（bob.jar 238 MB，下一步单独复制）、`.editor_settings`、`screenshot.png`。
`.gitignore` 里已有对应规则，复制后保留。

## 2. 必改清单

| 文件 | 改什么 | 不能漏 |
|---|---|---|
| `game.project` | `title`、`version`、`dependencies#0`（框架 commit/tag）、`[display]` 宽高 | `[script] shared_state = 1`（跨集合共享全局）、`[bootstrap] main_collection` |
| `main.collection` | proxy 的 `collection:` 属性 | **写源路径** `/menu/menu.collection`，不是 `.collectionc` |
| `script/session.script` | `app_id`、存档槽位名、`defaults()` / `validate()`、`sys.get_config_string` 的配置前缀、共享全局名 | init 里 `msg.post(".", "acquire_input_focus")` |
| `script/world.script` | 玩法逻辑、配置前缀 | 与 session 的消息名保持一致 |
| `input/game.input_binding` | 动作名 / 触发器 | 改动作名要同步改所有 `on_input` / `handle_input` |
| `menu/`、`game/`、`hud/`、`assets/` | 场景、GUI、图片、atlas、字体 | 按新玩法裁剪 |

跨集合通信固定套路：常驻层把 URL 写进共享全局（`shared_state = 1`），
子场景起来后发 `xxx_ready` 报到，常驻层用 `on_message` 的 **`sender`** 回包。
不要手写 `"proxy_id/obj#comp"` 这类内部路径，bob 下解析不到。

## 3. 依赖

`dependencies` 全部用 `https://codeload.github.com/<owner>/<repo>/zip/<sha>` 格式
（`github.com/.../archive/...` 在本机网络会被重置）：

```
dependencies#0 = https://codeload.github.com/cdmstrong/defold-game-framework/zip/<sha>
dependencies#1 = https://codeload.github.com/Insality/druid/zip/9a5171377fc2f7fba68fea4f2c117ee6a25d28a4
dependencies#2 = https://codeload.github.com/britzl/monarch/zip/5c33c39830489925493163e741d5b22b4e5e3b9d
dependencies#3 = https://codeload.github.com/Insality/defold-event/zip/384813497c25ff41d34ab1efdb1163217dc9dd26
```

- Defold 依赖**扁平解析**：框架自己声明过的第三方库，游戏仓库仍要全部再声明一遍。
- codeload 并发下载偶发 `Failed to fetch`，可重试；离线时把 ZIP 放本地 HTTP 服务
  （`python3 -m http.server 8899 --bind 127.0.0.1`，服务必须以后台任务常驻，用 `&` 会被回收）。
- 框架升级：在 `game-framework`（本地工作副本，无 `.git`）改 → 同步到 `defold-game-framework`
  （GitHub 发布仓库）→ `commit` + 打 tag + 重新打包含 `framework/`（含 `framework/docs/`）的 ZIP
  → 游戏改 `dependencies#0` 一行 → `resolve` + `build` 复验。

## 4. 编译（顺序不能反）

```bash
JAVA=/Applications/Defold.app/Contents/Resources/packages/jdk-25.0.4.1+1/bin/java
$JAVA -jar .tools/bob.jar --root . resolve
$JAVA -jar .tools/bob.jar --root . --output build/arm64-macos --platform arm64-macos \
      --variant debug --archive build
$JAVA -jar .tools/bob.jar --root . --output build/arm64-macos --platform arm64-macos \
      --variant debug --archive --bundle-output dist/arm64-macos build bundle
```

- 验证：build 产物里出现 `framework/` 的 `.luac`，说明依赖正确解析。
- 先 `--archive` 再 `--bundle`；`dist` 与 `build` 混用时 bob 增量可能不重编脚本。
- `bundle` 需要连 Defold Extender；只验证 `require` 用 `build` 即可。

## 5. 启动与验证

- 编辑器：Defold 1.14.1 打开 `game.project` → Fetch Libraries → `Cmd+B` Build & Run。
  **已运行的旧实例不会自动加载新代码，改完必须重新 Build & Run。**
- 无头（agent）：`defold_build` → `defold_run` → `defold_game_logs` / `defold_screenshot`；
  编辑器实例日志用 `.internal/editor.port` 的端口连 `defold_editor_logs`。
- `defold_hot_reload` 必须先 `defold_build`，否则 `build_first=false` 会推旧 `.scriptc`。
- 验收：真实编译 + 运行 + 日志/截图，不接受只查源码的口头结论。
- 同步复制 `AGENTS.md`（三步排障法 + 沉淀规则），并按新项目改掉里面的专属路径 / 前缀。

## 6. 收尾

```bash
git init && git add -A && git commit -m "feat: <游戏名> v0.1.0"
```

## 7. 高频坑速查

1. 持有 collection proxy 的 GO 没 `acquire_input_focus` → 子场景**所有**输入失效（见踩坑记录）。
2. `local function` 声明在调用点之后 = nil，`luac -p` 查不出来。
3. `msg.post("@system:","exit")` 在 1.14 报 `Field code not specified`，用 `sys.exit(0)`。
4. 场景切换期 post 到已卸载 socket 报错：用 `pending` / `pending_unload` 门控。
5. GUI `disable` 会连带隐藏子文本，置灰用 `gui.set_color`。
6. 冒烟钩子会刷高存档，接真实渠道前清档。
