# Defold Game Framework 实施文档

当前阶段：v1.1.0 可用性修复已完成（广告异步链路、存档错误语义、槽位分组、导航超时），
修复详情见 [v1.1.0 修复验证记录](verification/v1.1.0-fixes.md)。

1. [批量创建新游戏手册](creating-games.md)
2. [两层 UI 与品类复用](architecture/two-layer-ui.md)
3. [v1.1.0 修复验证记录](verification/v1.1.0-fixes.md)

本仓库是纯框架库（`framework/` + `game_modules/`），不含示例游戏；示例与开发工作区在本地 `game-framework/` 目录维护。库 ZIP 由 `scripts/export-libraries.py` 导出，framework 版本号跟随本仓库 git tag。
