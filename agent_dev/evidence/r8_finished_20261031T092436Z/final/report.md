# final 实验分析

每组固定分母：35 题、435 条用例；未生成、编译失败及调用失败均不从分母删除。
当前为未完成快照，组间覆盖不同，不能据此比较模型或框架优劣。

|框架|模型|实际尝试|CODESYS 首次→最终|用例首次→最终|整题通过|OpenPLC|双平台且用例全过|
|---|---|---:|---|---|---:|---:|---:|
|custom|deepseek-v4pro|5/35|4/35 → 5/35|28/435 → 32/435|3/35|5/35|3/35|
|codex|deepseek-v4pro|4/35|3/35 → 3/35|22/435 → 22/435|2/35|4/35|2/35|
|custom|minimax-m27|4/35|2/35 → 2/35|15/435 → 15/435|1/35|3/35|1/35|
|codex|minimax-m27|4/35|2/35 → 2/35|13/435 → 13/435|0/35|3/35|0/35|

## 时间、用量和费用

|框架/模型|候选数|分钟|已返回输入/输出 token|已返回费用估计|费用未知尝试|
|---|---:|---:|---:|---:|---:|
|custom/deepseek-v4pro|9|15.20|10666 / 37839|0.8829|1|
|codex/deepseek-v4pro|4|12.32|32614 / 33476|0.9459|0|
|custom/minimax-m27|5|12.92|5828 / 34334|0.2375|0|
|codex/minimax-m27|13|12.14|100586 / 21222|0.3077|0|

整题通过列采用 CODESYS 编译与功能用例口径；OpenPLC 单列。功能行为由扫描解释器执行，未主张物理 PLC 运行。

## LTL 状态

- CODESYS custom/deepseek-v4pro：{'passed': 5, 'not_run': 30}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS codex/deepseek-v4pro：{'passed': 3, 'not_run': 32}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS custom/minimax-m27：{'not_run': 32, 'passed': 2, 'failed': 1}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS codex/minimax-m27：{'passed': 2, 'not_run': 33}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- custom/deepseek-v4pro：{'timeout': 1, 'bounded_pass': 2, 'truncated': 1, 'violated': 1, 'not_run': 30}；规约固定分母 175，界内通过 13、确认违反 1、环境外反例 0、未完成或未判定 161。
- codex/deepseek-v4pro：{'truncated': 1, 'bounded_pass': 1, 'timeout': 1, 'not_run': 32}；规约固定分母 175，界内通过 6、确认违反 0、环境外反例 0、未完成或未判定 169。
- custom/minimax-m27：{'not_run': 33, 'bounded_pass': 1, 'timeout': 1}；规约固定分母 175，界内通过 6、确认违反 0、环境外反例 0、未完成或未判定 169。
- codex/minimax-m27：{'violated': 1, 'not_run': 33, 'timeout': 1}；规约固定分母 175，界内通过 0、确认违反 1、环境外反例 0、未完成或未判定 174。

FIFO 原题禁止同时请求入队和出队。仅由此类轨迹产生的反例单列，不能据此断言原题范围内程序错误；该类也不计为通过。

bounded_pass 为有限输入域、固定绑定、给定深度内结论；截断、超时、无法判定和工具错误均不算规约通过。

共享账本累计计入 15.325449 元，含未知预留 0.487403 元；不是上游实际账单。
