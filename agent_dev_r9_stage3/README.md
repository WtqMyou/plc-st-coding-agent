# R9 第三阶段独立开发与四组准备性实验

本目录来自已结束的 agent_dev_r9，来源见 ORIGIN_STAGE3.json；原 R9 和 R8 保持不变。

本阶段补充真实 CODESYS 支持的枚举解析与执行，澄清通用提示中的逐题复位语义，并在新汇总中读取实际嵌套的 LTL 检查记录。原题库、数字期望、费用账本与未知预留保留。

当前入口以 [第三阶段冻结方案](docs/R9第三阶段四组准备性实验_20261101.md) 为准。两题 × 两模型 × 两框架共8题次、最多16次生成，单题1200秒，CODESYS门控、最多30秒LTL检查。本阶段最多分配原诊断剩余额度中的7.50元，总授权仍为75元，原诊断累计上限仍为44.011998元。

这是准备性小样本，不是35题正式四组结果。新旧成绩不能混用；本轮多项修复也不支持单因素归因。此前代码、配置和验收证据随副本保留供追溯，旧验收源码哈希不适用于本轮。

离线验收：

    python -B -X utf8 scripts/validate_continuation.py --out evidence/stage3_validation_20261101

准备和运行须先有当前验收，冻结并推送后才启动付费入口：

    python -B -X utf8 scripts/r9_four_group_readiness.py --prepare --validation evidence/stage3_validation_20261101/validation.json
    python -B -X utf8 scripts/r9_four_group_readiness.py --live
    python -B -X utf8 scripts/sync_r9_stage3.py --publish

[GitHub 状态快照](../progress/evidence/r9_four_group_stage3_20261101/实验状态.md)；本机HTML仍为 http://127.0.0.1:8879/status.html 。运行依赖本机开机联网。新的未知费用或接口故障停止，不自动重试。

五道工业题的人工工艺复核仍待刘晏铭确认，[材料包说明](../progress/review_liu_20261101/README.md)保留。枚举支持范围以实际测试为准；复杂常量表达式等未实现语法不宣称支持。
