# r3字符串诊断证据

- acceptance.json：最终验收与范围。
- offline.json：531条参考用例、33项检查、新平台矩阵与既有参考证据的绑定。
- root_cause.json：固定候选哈希、历史CODESYS拒绝和OpenPLC接受记录。
- codesys_probes.json、openplc_probes.json：各8项对照；另两份 indexing_probes.json 各2项，总20项。
- native_matrix.json：20项对照的统一索引，接受与拒绝均保留。
- native_boundaries.json：额外1次自研MiniMax候选的CODESYS边界裁定。
- 两份测试日志：12项r2复验、21项r3检查。

所有源程序和模型候选保持原样。原生接受只表示对应入口完成编译/打包，不等于功能验证或现场PLC执行。未修改旧证据，没有付费模型调用。

[最终评分](../v13_r3_rescore_20261108b/重评分结果.md) 与 [版本说明](../../v13_r3/README.md)。
