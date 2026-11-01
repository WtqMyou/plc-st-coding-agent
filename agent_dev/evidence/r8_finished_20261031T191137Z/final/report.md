# final 实验分析

每组固定分母：35 题、435 条用例；未生成、编译失败及调用失败均不从分母删除。
本阶段已覆盖全部题目。

|框架|模型|实际尝试|CODESYS 首次→最终|用例首次→最终|整题通过|OpenPLC|双平台且用例全过|
|---|---|---:|---|---|---:|---:|---:|
|custom|deepseek-v4pro|35/35|28/35 → 33/35|312/435 → 372/435|21/35|34/35|21/35|
|codex|deepseek-v4pro|35/35|26/35 → 31/35|272/435 → 331/435|19/35|33/35|19/35|
|custom|minimax-m27|35/35|16/35 → 18/35|117/435 → 138/435|6/35|21/35|6/35|
|codex|minimax-m27|35/35|19/35 → 29/35|173/435 → 260/435|13/35|31/35|13/35|

## 时间、用量和费用

|框架/模型|候选数|分钟|已返回输入/输出 token|已返回费用估计|费用未知尝试|
|---|---:|---:|---:|---:|---:|
|custom/deepseek-v4pro|51|99.42|77388 / 281993|6.5651|0|
|codex/deepseek-v4pro|48|106.85|409521 / 295661|9.2181|0|
|custom/minimax-m27|46|140.35|63298 / 407245|2.8075|0|
|codex/minimax-m27|80|112.49|626465 / 189666|2.2979|1|

原始记录中的未发出暂停事件共 1 次，单独保留，不计入请求次数或费用未知尝试；真正的上游超时仍计入。
表中候选数按已发出的生成尝试统计，包含截断和调用失败；原始暂停留痕完整保留。
整题通过列采用 CODESYS 编译与功能用例口径；OpenPLC 单列。功能行为由扫描解释器执行，未主张物理 PLC 运行。

## LTL 状态

- CODESYS custom/deepseek-v4pro：{'passed': 33, 'not_run': 2}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS codex/deepseek-v4pro：{'passed': 31, 'not_run': 3, 'failed': 1}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS custom/minimax-m27：{'not_run': 15, 'passed': 18, 'failed': 2}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS codex/minimax-m27：{'passed': 29, 'not_run': 4, 'failed': 2}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- custom/deepseek-v4pro：{'timeout': 4, 'bounded_pass': 12, 'truncated': 16, 'tool_error': 1, 'not_run': 2}；规约固定分母 175，界内通过 47、确认违反 0、环境外反例 0、未完成或未判定 128。
- codex/deepseek-v4pro：{'truncated': 17, 'bounded_pass': 9, 'timeout': 4, 'not_run': 4, 'tool_error': 1}；规约固定分母 175，界内通过 36、确认违反 0、环境外反例 0、未完成或未判定 139。
- custom/minimax-m27：{'not_run': 17, 'bounded_pass': 4, 'timeout': 4, 'truncated': 8, 'tool_error': 1, 'violated': 1}；规约固定分母 175，界内通过 19、确认违反 2、环境外反例 0、未完成或未判定 154。
- codex/minimax-m27：{'violated': 8, 'not_run': 6, 'timeout': 5, 'bounded_pass': 6, 'tool_error': 1, 'truncated': 9}；规约固定分母 175，界内通过 25、确认违反 13、环境外反例 0、未完成或未判定 137。

FIFO 原题禁止同时请求入队和出队。仅由此类轨迹产生的反例单列，不能据此断言原题范围内程序错误；该类也不计为通过。

bounded_pass 为有限输入域、固定绑定、给定深度内结论；截断、超时、无法判定和工具错误均不算规约通过。

共享账本累计计入 34.011998 元，含未知预留 0.659229 元；不是上游实际账单。
