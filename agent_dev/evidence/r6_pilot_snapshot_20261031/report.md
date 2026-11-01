# pilot 实验分析

每组固定分母：6 题、75 条用例；未生成、编译失败及调用失败均不从分母删除。
当前为未完成快照，组间覆盖不同，不能据此比较模型或框架优劣。

|框架|模型|实际尝试|CODESYS 首次→最终|用例首次→最终|整题通过|OpenPLC|双平台且用例全过|
|---|---|---:|---|---|---:|---:|---:|
|custom|deepseek-v4pro|3/6|2/6 → 2/6|35/75 → 35/75|2/6|2/6|2/6|
|codex|deepseek-v4pro|3/6|3/6 → 3/6|44/75 → 44/75|2/6|3/6|2/6|
|custom|minimax-m27|2/6|2/6 → 2/6|35/75 → 35/75|2/6|2/6|2/6|
|codex|minimax-m27|2/6|2/6 → 2/6|34/75 → 34/75|1/6|2/6|1/6|

## 时间、用量和费用

|框架/模型|候选数|分钟|已返回输入/输出 token|已返回费用估计|费用未知尝试|
|---|---:|---:|---:|---:|---:|
|custom/deepseek-v4pro|3|5.38|3779 / 14182|0.3294|0|
|codex/deepseek-v4pro|3|8.08|25035 / 19064|0.5846|0|
|custom/minimax-m27|2|5.42|2267 / 12322|0.0855|0|
|codex/minimax-m27|2|3.47|15112 / 4228|0.0531|0|

整题通过列采用 CODESYS 编译与功能用例口径；OpenPLC 单列。功能行为由扫描解释器执行，未主张物理 PLC 运行。

## LTL 状态

- CODESYS custom/deepseek-v4pro：{'passed': 2, 'not_run': 4}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS codex/deepseek-v4pro：{'passed': 3, 'not_run': 3}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS custom/minimax-m27：{'passed': 2, 'not_run': 4}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- CODESYS codex/minimax-m27：{'passed': 2, 'not_run': 4}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。
- custom/deepseek-v4pro：{'bounded_pass': 1, 'timeout': 1, 'not_run': 4}；规约固定分母 34，界内通过 4、确认违反 0、环境外反例 0、未完成或未判定 30。
- codex/deepseek-v4pro：{'bounded_pass': 1, 'timeout': 1, 'truncated': 1, 'not_run': 3}；规约固定分母 34，界内通过 4、确认违反 0、环境外反例 0、未完成或未判定 30。
- custom/minimax-m27：{'bounded_pass': 1, 'timeout': 1, 'not_run': 4}；规约固定分母 34，界内通过 4、确认违反 0、环境外反例 0、未完成或未判定 30。
- codex/minimax-m27：{'violated': 1, 'timeout': 1, 'not_run': 4}；规约固定分母 34，界内通过 2、确认违反 1、环境外反例 1、未完成或未判定 30。

FIFO 原题禁止同时请求入队和出队。仅由此类轨迹产生的反例单列，不能据此断言原题范围内程序错误；该类也不计为通过。

bounded_pass 为有限输入域、固定绑定、给定深度内结论；截断、超时、无法判定和工具错误均不算规约通过。

共享账本累计计入 5.828037 元，含未知预留 0.482895 元；不是上游实际账单。
