# STBench F1.4 题库交接 · P1 平台复核补充

课程题库和首轮消息沿用 F1.4。CODESYS V3.5 SP22 Patch 4 的原接口抽查有 2 题编译通过、1 题失败，另外 32 题此次未抽查。公共 FIFO 在本地解释器通过 31/31 条功能用例，在该模板上编译报 10 个错误。独立的 DINT 版本放在 `platform_review/portable`，供目标环境单列验收。[编译反馈、变更与复验方法](platform_review/平台复核与变更记录.md)

本包包含 20 道课程公共题、15 道自建题、35 份参考 ST、规约、测试、来源和本轮复核记录。公共题发给模型的首轮用户消息逐字取自课程英文原文，含原接口表。自建题使用本版的公开需求、接口与规约。可直接将 `agent_inputs.json` 中对应题号的 `user` 字符串用于两个 Agent 的首轮用户消息。该文件不含参考代码或功能用例期望值。

## 运行与复核

在解压后的工程根目录运行，实测环境为 Python 3.13.9。

```text
python -B -X utf8 run.py
python -B -X utf8 verify_release.py
python -B -X utf8 task.py public-hard-04 --prompt --output fifo-prompt.txt
python -B -X utf8 task.py public-hard-04 --candidate datasets/public/tests/public-hard-04.reference.st --output fifo-score.json
```

第一条执行全库参考程序；第二条检查文件指纹、原文、评分分母、轨迹公式及定向错解。最后两条示范导出完整题面与按相同功能入口评定单份 ST 答卷。候选结果中列出每个失败用例的期望和实际值。独立有界搜索可运行 `python -B -X utf8 review/checks/bounded.py --declared-limits --out 新的有界报告.json`。

本版参考解 **35/35 题、946/946 条功能用例通过**。325 条非空 LTL 在实际用例轨迹上得到 **1225/1225 个通过判定**。同一公式在不同轨迹上可产生多次判定。声明预算内的独立搜索有 15 题完成、15 题到限、5 题因没有任务时钟模型而未定。后五题的具体时间边界已在有时间戳的功能轨迹实测。另有闸门、灌装的 8 拍 SMT 及多泵的扩额复验。原 F1.4 交付采用本地解释器。P1 另收录了队友随后完成的三道题 CODESYS 离线编译日志；本轮无 PLC 设备运行、OpenPLC 编译或模型调用。

## 交接文件

- [本轮修改与逐题复核](修改与逐项复核记录.md) 含 13 题采纳表、归档答卷复现和全库逐题差异。
- [离线浏览题面与测试](修订题面与用例表.html) 或按编号查阅 [首轮题面](agent_inputs.json)。
- [课程来源](sources/课程原题.json)、[35 题来源索引](sources/index.json)、[逐组功能成绩](evidence/full_run.json)、[有界检查范围](有界检查逐题复核.md)。
- [历史材料](history/README.md) 保存进件说明和之前的审核记录；当前实验请记录本包版本、题号、首轮文本散列和判分文件散列。旧 r8/r6 的结果按当时的版本保存。
