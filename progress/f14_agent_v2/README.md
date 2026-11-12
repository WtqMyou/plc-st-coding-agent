# Agent v2 修复与独立实验

本目录是2026-11-12对Agent输出与验证链路的修订版本。旧版工程、正式成绩和完整交接包均保留。

已实现的调整：

- 两框架共享明确的 FUNCTION_BLOCK 输出契约，原始题面和接口保持原文。
- 支持 `structured text` 等多词代码围栏，仅提取代码，不替模型补代码或更改程序类型。
- 为扫描解释器新增 R_TRIG/F_TRIG 状态、CLK输入与Q输出绑定、BYTE/WORD/DWORD/LWORD位访问。
- 完整功能块用真实CODESYS区分编译失败和本地检查器未建模；后者单列未决，避免把工具能力限制当成模型逻辑错误触发修复。

`release`保留全部35题、946条功能用例、原参考程序和规约。相对于`progress/f14_candidate/release`，仅两个解释器/检查器文件发生修改，指纹见`revision_manifest.json`。

`diagnostics`保存CODESYS纯仿真核验和140份旧答卷的免费重放。原有功能通过题全部保留；6份答卷增加通过用例，其中4份达到整题通过。此项是修复验证，不是新版模型成绩。

启动前运行`progress/tools/f14_v2_offline.py`完成两模型两框架共140条本地通道检查，使用本地固定响应替代付费API。然后通过`progress/tests/test_f14_v2.py`检查预算保护、反馈修复、无重试及新语义。正式运行入口为`progress/tools/f14_v2_study.py`，先`prepare`，冻结并推送Git，再`live`。

拟议批次目录：`E:/PLC_Dev/evidence/real_experiments/f14_v2_20261112`。状态页：`http://127.0.0.1:8886/status.html`。正式新批次必须在用户确认预算范围后启动，并以独立报告展示新结果。
