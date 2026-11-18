# platformer — 横版跳跃 / 跑酷骨架

Sky Climber 的骨架快照，`skeleton: "project"`：整份复制就是一个能跑的新项目。
机制说明见 [`template.json`](template.json)；跨项目 SOP 见
[`framework/docs/project-bootstrap.md`](../../framework/docs/project-bootstrap.md)。

## 结构

```
game.project          title/version/display/dependencies；shared_state = 1 必须保留
main.collection       loader：session.script + menu_proxy + game_proxy
script/session.script 唯一存档写入者 + 场景调度 + _G.SKY_SESSION 共享 URL
script/world.script   玩法主循环
menu/                 主页 / 商店
game/                 对局（玩家、金币、植物、石头、平台）
hud/                  局内 HUD
input/                输入绑定（改动作名要同步改所有 on_input）
assets/               atlas / 图片 / zh.font（ArialUnicode.ttf 需自备）
```

## 变成新游戏要改的四处

1. `game.project`：`title`、`version`（→ `0.1.0`）、`[display]` 宽高、`dependencies#0`
2. 全局标识：`_G.SKY_SESSION` → `_G.<GAME>_SESSION`、`climber.` 配置前缀 → `<game>.`、
   `app_id = "sky_climber"`、`Save:load("game")` 槽位名与存档字段
3. `menu/` `game/` `hud/` `assets/`：按新玩法裁剪
4. `assets/fonts/ArialUnicode.ttf`：从任一游戏项目拷（约 22 MB，不进 git）

## 先验证能跑再动玩法

```bash
JAVA=/Applications/Defold.app/Contents/Resources/packages/jdk-25.0.4.1+1/bin/java
$JAVA -jar .tools/bob.jar --root . resolve
$JAVA -jar .tools/bob.jar --root . --output build/arm64-macos --platform arm64-macos \
      --variant debug --archive
find build/arm64-macos/framework -name '*.luac' | wc -l   # 应为 15，少了说明依赖没解析到
```
