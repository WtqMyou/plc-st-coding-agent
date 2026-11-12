# 可复核成果数据

本轮F1.4-P1完整140题次、235请求数据的独立描述性汇总，未调用生成模型或重算正式成绩。

自研与Codex本轮合计功能通过均为28/70；自研MiniMax13/35、Codex MiniMax11/35，自研在该配置小幅领先。反馈修复后总体由36/140提升至56/140，新增20个通过题次。

可直接引用的成果表述、原工程、测试记录及给两位同学的资料均整理在[Agent交接入口](../../handoff_agent_20261112/README.md)。最终PPT/视频、项目报告汇总与汇报由原分工同学完成，Agent侧提供完整开发测试资料。

`outcomes.json`包含原始输入指纹、四组数据和三个反馈示例索引；复核命令：`python -B -X utf8 progress/tools/analyze_f14_outcomes.py --check`。
