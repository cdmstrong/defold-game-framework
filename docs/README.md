# Defold Game Framework 实施文档

当前阶段：v1.1.0 可用性修复已完成（广告异步链路、存档错误语义、槽位分组、导航超时），
修复详情见 [v1.1.0 修复验证记录](verification/v1.1.0-fixes.md)。

## 必读

1. [批量创建新游戏手册](creating-games.md)
2. [两层 UI 与品类复用](architecture/two-layer-ui.md)
3. [v1.1.0 修复验证记录](verification/v1.1.0-fixes.md)

## 设计与历史记录

4. [工程架构与 V1 范围](architecture/architecture.md)
5. [模块 API 合约](architecture/api-contracts.md)
6. [任务顺序与验收](planning/implementation-plan.md)
7. [依赖锁定清单](planning/dependencies.json)
8. [miner 示例规划](planning/miner.md)
9. [用户原始方案](references/studio-proposal.md)

验证记录：[M0](verification/m0.md) · [M1](verification/m1.md) · [M2](verification/m2.md) ·
[M3](verification/m3.md) · [M4](verification/m4.md) · [miner](verification/miner.md) ·
[v1.1.0 修复](verification/v1.1.0-fixes.md)

本仓库是框架库（`framework/` + `game_modules/`），示例代码在 `examples/`（不进 `include_dirs`，不随依赖导出）。
库 ZIP 由 `scripts/export-libraries.py` 导出，framework 版本号跟随本仓库 git tag。

> 旧的本地工作区 `game-framework/` 已删除，其中的脚本、示例、设计文档均已并入本仓库。
