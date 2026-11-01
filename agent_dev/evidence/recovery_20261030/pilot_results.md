# 代表题试跑结果（含未运行项）

表中费用仅为已返回用量的公开价估计；共享账本另保留未确认费用。功能测试为解释器执行，平台为真实编译。

|框架|模型|已尝试/题数|CODESYS 首次/最终|用例|整题|OpenPLC|token|已返回费用估计|
|---|---|---:|---|---|---|---|---:|---:|
|custom|deepseek-v4-pro-0813|1/6|16.7%/16.7%|27/75|16.7%|1/6|12704|0.2524|
|codex|deepseek-v4-pro-0813|1/6|0.0%/0.0%|0/75|0.0%|0/6|13575|0.1704|
|custom|MiniMax-M2.7|1/6|0.0%/0.0%|0/75|0.0%|0/6|0|0.0000|
|codex|MiniMax-M2.7|0/6|0.0%/0.0%|0/75|0.0%|0/6|0|0.0000|

## 验证状态

- custom/deepseek-v4pro：{'bounded_pass': 0, 'violated': 0, 'timeout': 0, 'truncated': 0, 'inconclusive': 0, 'tool_error': 1, 'not_run': 0}
- codex/deepseek-v4pro：{'bounded_pass': 0, 'violated': 0, 'timeout': 0, 'truncated': 0, 'inconclusive': 0, 'tool_error': 0, 'not_run': 1}
- custom/minimax-m27：{'bounded_pass': 0, 'violated': 0, 'timeout': 0, 'truncated': 0, 'inconclusive': 0, 'tool_error': 0, 'not_run': 1}
- codex/minimax-m27：{'bounded_pass': 0, 'violated': 0, 'timeout': 0, 'truncated': 0, 'inconclusive': 0, 'tool_error': 0, 'not_run': 0}

## 共享预算（报告生成时点）

累计计入 0.612114 元，其中未确认预留 0.185358 元；不是上游实际账单。
账本状态：Unconfirmed upstream result; reservation retained
