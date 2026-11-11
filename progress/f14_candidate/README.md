# F1.4-P1候选接入

此目录保存新版题库的免费准入组件。后续独立批次已建立于[F1.4-P1实验入口](../f14_study/README.md)，采用用户最新授权的190元上限和80元暂停点；原review-r8/r7及已完成140题次不迁移、不重算。下文保留组件验收时的范围。

- `release/`：队友F1.4-P1交付包的305个原始文件，304项冻结指纹保持一致。课程题面、接口、参考ST、测试和首轮用户消息均保留。
- `bridge.py`、`judge_worker.py`：在独立Python进程加载F1.4裁判，避免与旧r7的同名`stbench`包混用。保留`group`、`expected_any`、`scan_interval_ms`；功能执行为Python解释器，不能代称CODESYS运行。
- `codex_transport.py`：候选CLI通道。首轮任务文本以UTF-8原字节写入stdin；公共指导通过`developer_instructions`提供。CLI仍会加入自身环境上下文，实际上游消息已归档。修复轮携带原代码及裁判反馈，两个框架的提示策略尚未正式冻结。
- `feedback_probe.py`：独立的形式反馈接线探针，不是第36题，不计入946条或模型成绩。
- `compatibility/`：两份独立参考编译补丁及其清单；只用于参考程序验证。不会改写生成候选，也未改动`release/`。

本地假响应已覆盖140条首轮通道及12条三类反馈修复通道，另以4条通道核验实际CODESYS错误诊断。使用参考ST作为本地假响应，未向外部生成模型提交任何请求。CLI工作目录不含题库、参考答案或测试期望；首轮请求不含参考ST。

准入时的限制：原包真实编译32/35；双字移位、IPv4解析的独立参考补丁通过后可验证34/35，课程FIFO的VARIANT接口仍不被当前CODESYS支持。DINT开放数组变体及其14步仿真仅作为独立补充。后续批次已将该限制明确为原生可评价34题、FIFO平台限制另列，功能保留35题；最终策略、预算及调度规则见独立入口。

[免费准入结果与下一步](../evidence/f14_admission_preflight_20261111/免费准入结果与下一步.md)记录范围、失败、预算和验收边界。

只读复核：

```powershell
python -B -X utf8 progress/tools/audit_f14_admission.py --check
python -B -X utf8 progress/tools/f14_native_feedback_routes.py --check
python -B -X utf8 progress/tools/analyze_full_r8b_results.py --check
```

这些复核依赖当前电脑`E:/PLC_Dev/evidence`的原始平台证据。仓库保存题库快照、参考源码、诊断、实际假响应请求、摘要和文件指纹，未发布本地二进制工程或API凭据。

配置依据：[Codex配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)的`developer_instructions`字段。此链接仅说明CLI配置方式，不支持任何实验成绩结论。
