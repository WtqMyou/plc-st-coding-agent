# Agent V5公共题定向改进小试

已停止，保留现场
已完成23/24题次，请求42/48；累计计入112.728371/210元。

六道公共题 × 两模型 × 两框架，每题至多一次修复。4题次并行、同模型最多2请求，原生编译独占。
改进：公开工程契约表、合法方言与结构体接口检查、代表性语义反馈。原题、参考程序、测试期望和规约均保持原版。
生成与修复提示不含参考答案、测试期望值或私有规约观察器；输入轨迹及实际输出属于执行反馈。

| 组别 | 完成/6 | CODESYS首次→最终/6 | 功能首次→最终/6 | 用例通过 | 修复新增 | 请求 | 工程表/6 |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: |
| 自研 DeepSeek | 5 | 3→5 | 1→2 | 98/123 | 1 | 11 | 6 |
| Codex DeepSeek | 6 | 6→6 | 2→4 | 107/123 | 2 | 9 | 6 |
| 自研 MiniMax | 6 | 3→6 | 0→1 | 69/123 | 1 | 10 | 2 |
| Codex MiniMax | 6 | 2→6 | 0→0 | 85/123 | 0 | 12 | 4 |

| 组别 | 完整代码首次→最终 | 形式状态 | 本轮计入/元 |
| --- | --- | --- | ---: |
| 自研 DeepSeek | 5→6 | {"not_run": 4, "inconclusive": 1, "truncated": 1} | 1.701429 |
| Codex DeepSeek | 6→6 | {"not_run": 1, "inconclusive": 3, "violated": 1, "truncated": 1} | 2.348145 |
| 自研 MiniMax | 5→6 | {"not_run": 3, "inconclusive": 3} | 0.205496 |
| Codex MiniMax | 5→6 | {"not_run": 5, "inconclusive": 1} | 0.392714 |

本轮最坏预留21.027911元；本轮未结算预留0.000000元。
费用含已结算估算及未确认预留，保留全部历史未知费用。继续使用备用Key，80元不暂停，210元为累计硬上限。
空正文、截断、调用错误不自动重发。身份不符、未知费用或公共工具故障停止并保留现场。
本轮为六题诊断，结果独立保留；功能、原生编译及有界形式状态分别统计。

题目：public-easy-01, public-easy-04, public-hard-03, public-medium-03, public-medium-04, public-medium-08

最近状态：{"state": "stopped", "at": "2026-11-12T20:34:05.719450+08:00", "completed": 23, "error": "RuntimeError: Isolated F1.4 worker failed: v5\\release\\stbench\\st\\interp.py\", line 517, in exec_stmt\n    while self._truthy(self.eval(st.args[0])):\n                       ^^^^^^^^^^^^^^^^^^^^^\n  File \"C:\\Users\\27478\\OneDrive\\桌面\\GenAI赋能工业编程\\homework\\finalwork\\progress\\f14_agent_v5\\release\\stbench\\st\\interp.py\", line 748, in eval\n    r = self.eval(node.args[1])\n        ^^^^^^^^^^^^^^^^^^^^^^^\n  File \"C:\\Users\\27478\\OneDrive\\桌面\\GenAI赋能工业编程\\homework\\finalwork\\progress\\f14_agent_v5\\release\\stbench\\st\\interp.py\", line 747, in eval\n    l = self.eval(node.args[0])\n        ^^^^^^^^^^^^^^^^^^^^^^^\n  File \"C:\\Users\\27478\\OneDrive\\桌面\\GenAI赋能工业编程\\homework\\finalwork\\progress\\f14_agent_v5\\release\\stbench\\st\\interp.py\", line 757, in eval\n    return self._call(node)\n           ^^^^^^^^^^^^^^^^\n  File \"C:\\Users\\27478\\OneDrive\\桌面\\GenAI赋能工业编程\\homework\\finalwork\\progress\\f14_agent_v5\\release\\stbench\\st\\interp.py\", line 917, in _call\n    return _wrap_int(int(v), dst)\n                     ^^^^^^\nValueError: invalid literal for int() with base 10: '.'\n"}
