# 最新Agent开发测试交接入口（2026-11-13）

最新完整140题次：自研DeepSeek33/35、Codex DeepSeek34/35、自研MiniMax13/35、Codex MiniMax11/35。自研合计46/70，Codex45/70；自研反馈修复新增14题，Codex新增10题。

新版交接包保留原工程、140题次306请求、真实编译工程与原始传输、最新结果分项CSV、PNG/SVG图表、真实修复案例及无密钥离线复验工具。MiniMax420/900秒等待批次和异常费用预留分别记录。旧版20261112交接包继续保留，最新主结果请以本版为准。

下载：[最新完整交接包（GitHub发布页）](https://github.com/WtqMyou/plc-st-coding-agent/releases/tag/handoff-20261113-v1)。完整ZIP约126.6 MB，解压后先双击`STAgent_20261113/00_先读我.html`，按页面里的PPT/视频、报告汇总、开发接手入口查看。

[直接下载ZIP](https://github.com/WtqMyou/plc-st-coding-agent/releases/download/handoff-20261113-v1/STAgent_20261113_full.zip) · [下载指纹清单](https://github.com/WtqMyou/plc-st-coding-agent/releases/download/handoff-20261113-v1/STAgent_20261113_full.manifest.json)。线上使用英文文件名，内容与本地中文文件名ZIP完全一致。

本地文件：`progress/Agent开发测试完整交接包_20261113_v2.zip`。包含20,040个原工程文件、140题次306次请求、205个真实编译工程、五组PNG/SVG图表、四个真实案例及离线工具。

[交付说明与成果主表](发布说明.md) · [包指纹与构建验收](../Agent开发测试完整交接包_20261113_v2.manifest.json) · [实际ZIP解压复验](ZIP解压复验.json) · [GitHub发布回执](GitHub发布回执.json)

SHA256：`ba4e2d35d97549d547ce98c88cb343f8bac28118118cfa3512aa2f72f50eaa9d`。源码冻结提交：`fd4953e3c2fb39811613dd8d53e207cb2d858303`。构建工具为`progress/tools/build_agent_handoff_20261113.py`，`v2`是本次构建编号。

已完成文件指纹、费用关联、精确补丁、原生nonce、946/946参考功能及案例复验；检查未调用生成模型，原账本1965条事件、211.178859元保持。敏感信息检查通过，不包含密钥、许可证与编译缓存。

Agent侧只交付开发测试工程与素材，PPT、视频与项目报告汇总按原分工由两位同学完成。默认离线查看与校验不调用生成模型。
