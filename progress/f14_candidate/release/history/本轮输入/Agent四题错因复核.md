# 自研 Agent × DeepSeek 四题错因复核

2026-11-11。复核对象为批次 b 归档到 61/140 时，自研 DeepSeek 已做的 15 道题。选取其中三道功能失败题和一道功能通过却被 LTL 找到反例的题。按当时实际发给模型的题面核查，使用 r8 数据和该版裁判调用的 r5 功能执行器，本地重放正式选中的答卷、参考 ST 和下列定向输入。LTL 性质编号来自原实验归档，本轮用对应输入验证其反例。[实验快照](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/实验状态.md) · [功能判分入口](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/v13_r7/r7_judge.py)

| 题号 | 候选通过 / 功能断言 | 参考解 | 首个问题 |
|---|---:|---:|---|
| public-hard-02 输送线 | 62/64 | 64/64 | 两条扣分输入违反路线合同；改为合法路线后，启动拍仍会多输出一次右行 |
| public-hard-05 机械臂 | 82/88 | 88/88 | 测试要求在同一扫描跳过多个已完成步骤，公开题面对这一点交代不足 |
| public-medium-03 移动平均 | 14/17 | 17/17 | 候选按旧窗口限制历史计数，扩窗后少算一个样本 |
| public-hard-03 配方管理 | 19/19 | 19/19 | 同拍新增和删除或修改时，候选悄悄丢弃第二个请求，违反 S4、S5 |

## public-hard-02　输送线

从初态令 `processSequence=[2,5,0,0,0,0,0,0]`。首拍 `sensor1=station1Start=sensor2=TRUE`，其余布尔输入为假。

| 输入长度 | 有效路线 | 参考输出（左，右） | 候选输出（左，右） |
|---:|---|---|---|
| 1（归档失败用例第一拍） | [2] | (FALSE, FALSE) | (FALSE, TRUE) |
| 2（另行复现） | [2,5] | (FALSE, FALSE) | (FALSE, TRUE) |

第一行属于 `peer-ha-short-route-1/2` 的防御测试。题面保证最后一个有效站为 5，这两拍却使用了以 2 结尾的有效路线。第二行只改长度，符合公开路线要求，且题面未要求各工位传感器互斥。目标工位 2 当拍已经报到位，候选的启动分支却直接输出右行，到下一拍才进入到站检查。可把合法输入纳入功能评分，把无有效末站的两拍列到异常输入测试，并公开异常行为要求。[模型收到的题面](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-hard-02.request_01.json) · [逐拍判分与代码](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-hard-02.json) · [正式用例](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/v13_r8/datasets/public/public-hard-02.json)

## public-hard-05　机械臂

从初态运行三拍，始终令 `ContinuousMode=EmergencyStop=TRUE`（急停未触发），每拍未列布尔输入均为假。

| 拍 | 当拍其余真输入 | 参考输出 | 候选输出 |
|---:|---|---|---|
| 1 | 无 | 全停 | 全停 |
| 2 | Start | 下行 | 下行 |
| 3 | DownLimitSwitch、GripLimitSwitch、UpLimitSwitch、RightLimitSwitch | 释放 | 全停 |

第 3 拍对应 `h05-31`。参考实现在同一扫描里连续检查到位反馈，跳过“下、抓、上、右、下”后输出释放。候选每拍只推进一步，到“抓”时抓取到位开关已经为真，就关闭了该动作。随后两拍继续与用例错位。六条失败来自同一段三拍断言及其副本。公开题面列出了动作顺序，但没有明确上述多步推进规则，还允许本用例同时给出上、下限位。若保留这一判法，应把同拍推进规则和允许的限位组合写入模型可见题面。[模型收到的题面](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-hard-05.request_01.json) · [逐拍判分与代码](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-hard-05.json) · [正式用例](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/v13_r8/datasets/public/public-hard-05.json)

## public-medium-03　移动平均

从初态开始，四拍均令 `cyclicExecution=TRUE`、`trigger=reset=FALSE`。下面是缩短后重新运行的输入。

| 拍 | 样本 | 窗口 | 参考均值 | 候选均值 |
|---:|---:|---:|---:|---:|
| 1 | 30 | 2 | 30 | 30 |
| 2 | 40 | 2 | 35 | 35 |
| 3 | 60 | 2 | 50 | 50 |
| 4 | 100 | 4 | 57.5 | 66.6666666667 |

候选的有效样本计数受旧窗口 2 限制。第四拍它只取 40、60、100，漏掉仍在缓冲区的 30。正式用例的首处分歧是 s8；s9、s10 要求在窗口非法时保持上次均值，沿用了 s8 的错误结果。第二次生成还混入以 `--` 开头的中文注释，静态检查失败，实验最终选回首稿。S6 已用累计样本数描述均值，但末句“只保留最近 windowSize 个样本”容易被理解成扩窗前可以永久丢弃旧样本。宜明确“最多保留最近 100 个有效样本，当前窗口只决定取多少个求平均”。[模型收到的题面](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-medium-03.request_01.json) · [逐拍判分与代码](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-medium-03.json) · [正式用例](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/v13_r8/datasets/public/public-medium-03.json)

## public-hard-03　配方管理

从空库启动，输入配方 `(recipeID=1, ingredientType=1, ingredientRatio=10, productionTemperature=105)`。下表每行从初态独立运行一拍，未列请求为假。

| 当拍请求 | 参考输出 | 候选输出 | 违反 |
|---|---|---|---|
| 新增＋删除 | 新增成功，删除失败，error=TRUE，status=0x8004 | 新增成功，删除失败，error=FALSE，status=0 | S4 |
| 新增＋修改 | 新增成功，修改失败，error=TRUE，status=0x8005 | 新增成功，修改失败，error=FALSE，status=0 | S5 |

参考程序按扫描开始时的库内容查找，所以同拍新增成功时，也能报告另一个请求找不到原配方。候选用互斥分支处理请求，新增成功就跳过删除或修改。S4、S5 明确要求每个请求沿当拍成功或报错，两条都被违反。19 条功能用例只覆盖无请求或单请求，可将这两条反例加入功能回归。若要进一步考核并发时的精确状态码，题面应写清按拍初数据库查找和多个错误同时发生时的优先顺序。[模型收到的题面](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-hard-03.request_01.json) · [逐拍判分与代码](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-hard-03.json) · [正式用例](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/v13_r8/datasets/public/public-hard-03.json)

## 归档里还有一个会误导排错的问题

配方用例 h03-2 的通过标志为真。把同一候选只运行到第 2 拍，前两个配方号为 `[1,0]`，与期望一致。读完整序列的归档，同一行的实际值却是 `[0,3]`，对应后续库状态。h03-5 的查询结果也有同类现象。应在每次扫描结束时复制数组、结构体的值，并用“只跑前缀”和“跑完整段”两种方式核对历史记录。这个问题影响对历史输出的解释；上述两个并发反例使用独立的单拍复现。[配方逐拍记录](https://github.com/WtqMyou/plc-st-coding-agent/blob/97725624b924990f6cdf38563d1fc17f5280502f/progress/evidence/full_r8_20261110b/jobs/custom_deepseek-v4pro/public-hard-03.json)

