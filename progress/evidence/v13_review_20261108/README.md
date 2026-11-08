# v1.3-review-r1 免费验收证据

技术验收完成，人工复审仍待刘晏铭确认；没有付费模型调用。

- `acceptance.json`：汇总结果及范围。
- `offline.json`：35 题 531 用例、严格接口结果、五题测试轨迹上的公式复验。
- `revision_tests.log`：11 项新检查通过，含错误实现/规约反例。
- `frozen_engine_regression.log`：原冻结引擎的 185 项回归通过。
- `codesys_controls.json`、`openplc_controls.json`：新跑的正确/故意错误程序控制。
- `codesys_references.json`、`openplc_references.json`：两平台各 35 份参考解真实编译通过；代码哈希与平台身份已再核对。平台工程保留在本机 E 盘。

修订版来源、生成规则、参考解依赖和技术冻结清单见 [版本说明](../../v13/README.md) 与 [清单](../../v13/snapshot_manifest.json)。给定测试轨迹通过不代表穷尽形式验证、PLCVerif 执行或现场工艺验收。

[历史候选重评分](../v13_rescore_20261108b/重评分结果.md) 为独立事后分析，不替换正式 R8 结果，其中一个字符串候选保留为工具未决。首次不完整重评分保留在后缀不带 b 的目录并标明状态。
