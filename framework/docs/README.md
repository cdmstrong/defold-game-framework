# framework/docs — 踩坑沉淀库（导航）

> **这是文件目录导航文档，主体是踩坑记录索引。**
> 遇到难解决的问题，第 1 步就是查这里；查完再去官方文档、论坛（顺序见各游戏仓库根目录的 `AGENTS.md`）。
>
> 本目录是**框架通用层**：随 `framework/` 打进依赖，所以每个游戏仓库都能查到同一份沉淀。
> 仓库层文档（规划、验证、许可证、旧版建游戏手册）在仓库根的 [`docs/README.md`](../../docs/README.md)，
> 那份**不随依赖**，只给框架维护者看。新项目里要能查到的内容，一律写在本目录。

## 这个目录为什么放在 `framework/docs/`

`framework/` 会整体打进依赖 ZIP 分发给所有游戏仓库，所以踩坑记录跟着框架走：
任何用本框架的游戏项目，都能在依赖里查到同一份沉淀，不用逐个项目重踩。

- 本地开发主路径：`/Users/chendongming/coding/auto-games/defold/game-framework/framework/docs/`
- 游戏仓库内查找：`find . -path "*framework/docs/README.md"`（依赖解压副本）
- ⚠️ **仓库关系**：`game-framework` 是**指向本仓库的软链**（`auto-games/defold/game-framework -> defold-game-framework`），
  只有一个仓库、一份 `.git`。**不要再做「本地副本 → 同步到发布仓库」的两步走**（对同一目录 `cp` 会报 same file）。
  流程改为：改文件 → `git commit`（+ 需要时打 tag）→ 游戏侧改 `dependencies#0` 一行。
- ⚠️ **已生成的发布包（`framework-releases/*.zip`）不含本目录**。要让新项目通过依赖拿到这些记录，
  需在发布仓库重新打包 / 发 tag，且打包命令要包含 `framework/` 整个目录。
  GitHub codeload 的整仓 ZIP **认不到** `.gitattributes export-ignore`，所以只能靠换发布物（库 ZIP）来瘦身。
- 本目录不参与游戏运行，纯 Markdown，不影响 Defold 资源编译。

## 导航表

### 踩坑记录

| 日期 | 主题 | 文档 | 关键词 | 适用版本 |
|---|---|---|---|---|
| 2026-11-19 | 233 乐园 MetaH5Ad 激励视频「看完没奖励/只有第一次能看」六层坑：全局日志函数缺失、SDK 半就绪、晚到事件覆盖、`0===''` 弱等号、回调异常吞事件、**JS 模板替换产生双重调用 IIFE（最终根因）**；附 Node vm 产物断言方法论与真机排障工具链 | [2026-11-19-233-leyuan-rewarded-ad-pitfalls.md](2026-11-19-233-leyuan-rewarded-ad-pitfalls.md) | 233乐园、MetaH5Ad、激励视频、html5.run、JS 模板替换、IIFE 双重调用、异步轮询、settle、status=4、看完没奖励、busy、回调异常、logBlue、JSON.stringify 循环引用、Node vm 复现 | Defold 1.14.1（wasm-web） |
| 2026-11-19 | .gui 文件 color.w 半透明不生效 | 2026-11-19-gui-file-color-w-alpha.md | gui alpha 透明 遮罩 blend set_color | 1.14.1 |
| 2026-11-19 | `msg.post(set_parent)` 传错字段名被静默忽略走默认值（keep_world_transform 默认 1）→ 子物件以创建点世界坐标挂载、不可见但判定仍生效（隐形杀手）；改用 `go.set_parent()` 函数（boolean 默认 false） | [2026-11-19-set-parent-keep-world-transform.md](2026-11-19-set-parent-keep-world-transform.md) | set_parent、keep_world_transform、keep_world_position、factory.create 局部坐标、go.get_world_position、隐形判定、消息字段静默忽略、消息与函数默认值不一致 | Defold 1.14.1 |
| 2026-11-19 | 改设计分辨率必须同步 GUI/判定坐标；「限制最大宽度」用 fixed_fit 而非 viewport 收缩；GUI/世界相机投影必须分开（GUI=窗口正交，共用 fixed_fit 会 fit²）；可选补偿方案（共享 fit 系数 + GUI 逆向缩放，未实现） | [2026-11-19-design-resolution-sync.md](2026-11-19-design-resolution-sync.md) | display.width、GUI 等比换算、fixed_fit、信箱、glViewport 不裁切、get_gui_projection、fit²、Adjust Reference、输入坐标自动转换、按钮判定区间、共享 fit 系数、逆向缩放、bob 增量不重编 gui | Defold 1.14.1 |
| 2026-11-18 | collection proxy 场景内点击完全无反应 | [2026-11-18-collection-proxy-input-focus.md](2026-11-18-collection-proxy-input-focus.md) | `acquire_input_focus`、输入栈、collection proxy、`on_input`、GUI 点击、场景切换 | Defold 1.14.1（机制通用于 1.x） |

### 流程 / SOP

| 文档 | 用途 |
|---|---|
| [project-bootstrap.md](project-bootstrap.md) | 新项目初始化 & 从现有项目复制启动（通用模板，不含具体游戏专属值） |
| [`../../docs/bootstrap/creating-games.md`](../../docs/bootstrap/creating-games.md) | 旧版《批量创建新游戏手册》（以 miner-game 为模板、历史 `examples/<游戏名>/` 结构，该目录已更名 `templates/`）。**与 `project-bootstrap.md` 是两套骨架，别混** |

## 官方资料入口（第 2 步用）

| 用途 | 地址 |
|---|---|
| 文档总导航 | https://defold.com/llms.txt |
| 手册全文（单文件检索） | https://defold.com/llms-manuals.txt |
| API 全文 | https://defold.com/llms-apis.txt |
| 官方示例 | https://defold.com/llms-examples.txt |
| 全部合并 | https://defold.com/llms-full.txt |
| 单篇手册 | `https://defold.com/llms/manuals/<name>.md` |
| 论坛（第 3 步） | https://forum.defold.com |

## 新增一篇的规矩

1. 文件名：`<YYYY-MM-DD>-<kebab-case-主题>.md`。
   同一主题再次踩坑 → 在原文追加「反例 / 补充」，不新建文件。
2. 八段模板：现象与复现 / **错误假设（走过的弯路，别删）** / 三步查证结果（框架 docs → 官方文档 URL+原文 → 论坛 URL）/ 根因（带日志证据）/ 修复 / 验证（真实编译+运行）/ 防再犯检查清单 / 关联 commit。
3. **必须回来更新上面的导航表**（主题、关键词、适用版本），否则等于没沉淀。
4. 直接在本目录写，然后 `git add` + `commit`（这里就是发布仓库，没有第二份副本要同步）。
   要让**已经存在的游戏**拿到，还要打 tag 并让游戏侧改 `dependencies#0`；游戏仓库的
   `.workbuddy/memory/` 只放一行索引。
5. 结论必须有证据：禁止「实测引擎不支持」这类没有日志 / 官方文档引用的归因。
