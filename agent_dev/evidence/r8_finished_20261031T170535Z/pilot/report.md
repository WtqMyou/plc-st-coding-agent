# pilot 实验分析

每组固定分母：6 题、75 条用例；未生成、编译失败及调用失败均不从分母删除。
本阶段已覆盖全部题目。

|框架|模型|实际尝试|CODESYS 首次→最终|用例首次→最终|整题通过|OpenPLC|双平台且用例全过|
|---|---|---:|---|---|---:|---:|---:|
|custom|deepseek-v4pro|6/6|2/6 → 2/6|35/75 → 35/75|2/6|3/6|2/6|
|codex|deepseek-v4pro|6/6|3/6 → 3/6|44/75 → 44/75|2/6|3/6|2/6|
|custom|minimax-m27|6/6|3/6 → 3/6|41/75 → 41/75|2/6|3/6|2/6|
|codex|minimax-m27|6/6|3/6 → 3/6|41/75 → 41/75|2/6|4/6|2/6|

## 时间、用量和费用

|框架/模型|候选数|分钟|已返回输入/输出 token|已返回费用估计|费用未知尝试|
|---|---:|---:|---:|---:|---:|
|custom/deepseek-v4pro|6|14.00|7800 / 43776|0.9892|0|
|codex/deepseek-v4pro|6|14.71|50305 / 41857|1.2505|0|
|custom/minimax-m27|6|19.89|7426 / 53018|0.3641|0|
|codex/minimax-m27|6|11.25|45988 / 23936|0.2351|0|

整题通过列采用 CODESYS 编译与功能用例口径；OpenPLC 单列。功能行为由扫描解释器执行，未主张物理 PLC 运行。

## LTL 状态

- CODESYS custom/deepseek-v4pro：{'passed': 2, 'not_run': 2, 'failed': 2}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS codex/deepseek-v4pro：{'passed': 3, 'not_run': 2, 'failed': 1}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS custom/minimax-m27：{'passed': 3, 'not_run': 2, 'failed': 1}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS codex/minimax-m27：{'passed': 3, 'not_run': 3}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- custom/deepseek-v4pro：{'bounded_pass': 1, 'timeout': 1, 'not_run': 4}；规约固定分母 34，界内通过 4、确认违反 0、环境外反例 0、未完成或未判定 30。
- codex/deepseek-v4pro：{'bounded_pass': 1, 'timeout': 1, 'truncated': 1, 'not_run': 3}；规约固定分母 34，界内通过 4、确认违反 0、环境外反例 0、未完成或未判定 30。
- custom/minimax-m27：{'bounded_pass': 1, 'timeout': 1, 'not_run': 3, 'violated': 1}；规约固定分母 34，界内通过 8、确认违反 1、环境外反例 0、未完成或未判定 25。
- codex/minimax-m27：{'violated': 2, 'timeout': 1, 'not_run': 3}；规约固定分母 34，界内通过 2、确认违反 3、环境外反例 1、未完成或未判定 28。

FIFO 原题禁止同时请求入队和出队。仅由此类轨迹产生的反例单列，不能据此断言原题范围内程序错误；该类也不计为通过。

bounded_pass 为有限输入域、固定绑定、给定深度内结论；截断、超时、无法判定和工具错误均不算规约通过。

共享账本累计计入 28.805046 元，含未知预留 0.659229 元；不是上游实际账单。
