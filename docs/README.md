# Defold Game Studio 实施文档

当前阶段：M0–M4 全部实现并验证；v1.1.0 完成一轮可用性修复（广告异步链路、存档错误
语义、槽位分组、导航超时），修复详情见 [v1.1.0 修复验证记录](verification/v1.1.0-fixes.md)。

1. [工程架构与 V1 范围](architecture/architecture.md)
2. [模块 API 合约](architecture/api-contracts.md)
3. [任务顺序与验收](planning/implementation-plan.md)
4. [候选依赖版本和 commit](planning/dependencies.json)
5. [用户原始方案](references/studio-proposal.md)
6. [批量创建新游戏手册](creating-games.md)

验证记录：[M0](verification/m0.md) · [M1](verification/m1.md) · [M2](verification/m2.md) ·
[M3](verification/m3.md) · [M4](verification/m4.md) · [miner](verification/miner.md) ·
[v1.1.0 修复](verification/v1.1.0-fixes.md)

game.project 当前入口为 `examples/miner/main.collection`（挖矿大亨示例游戏）。
