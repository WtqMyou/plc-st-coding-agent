# 成员二：PLC Coding Agent（前期工程）

当前为第八版请求窗口保护，实验目录为 `E:/PLC_Dev/evidence/real_experiments/campaign_75_window_r8`。2026-11-01 01:18 按用户要求从 104/140 个正式题次断点接续；本次完整时限超时仍计作失败，历史费用及未知预留保留，代表题与三轮开发不重跑。已修正暂停事件的请求统计，当前 139 项回归通过。实时进度见该目录的“实验状态.html”，每 15 秒刷新。本次接续见[正式超时接续与统计修复](docs/正式超时接续与统计修复_20261101.md)，此前进度见[第八版实验重启记录](docs/第八版实验重启_20261031.md)，窗口修复见[请求剩余时间修复](docs/请求剩余时间修复_20261031.md)。已有实验运行，不要启动重复流程。

本工程已整合成员一 stbench v1.2，当前为 35 题 / 435 条用例。当前适配契约为 `portable-frame-v4`，原 v2.1 交接包和历史试跑全部保留。实验模型为 DMXAPI 的 `deepseek-v4-pro-0813` 与 `MiniMax-M2.7`，累计预算仍为 75 元。已修复 Codex 超时、费用留痕、断点耗时、已知截断的有界修复及 FIFO 固定绑定检查。当前版本为第八版，上版调度修复见 [正式覆盖调度修复](docs/正式覆盖调度修复_20261031.md)，固定绑定说明见 [固定绑定与实验进度](docs/固定绑定与实验进度_20261031.md)，历史记录见 [Codex 超时接续](docs/Codex超时接续_20261030.md)和[代表题策略更新](docs/代表题策略更新_20261030.md)。

二次更新的采用范围、单位修正、超压计数修复及 PI 版本选择见 [二次更新整合说明](docs/二次更新整合说明.md)。上次 v2.0 交接包完整保留。

## 快速验收

在本目录运行，Python 3.10 及以上，无第三方运行依赖：

    python -B -X utf8 -m unittest discover -s tests -p "test_v2*.py" -v
    python -B -X utf8 -m stbench doctor
    python -B -X utf8 -m stbench verify-refs --out evidence/reference_tests.json
    python -B -X utf8 -m stbench platform-check --platform openplc --adapted --out evidence/openplc_adapted.json
    python -B -X utf8 -m stbench matrix --offline --adapted --out evidence/offline_matrix_v2.1/summary.json

一次运行全部离线回归和题库审计：

    python -B -X utf8 scripts/rebuild_selfmade.py
    python -B -X utf8 scripts/acceptance.py
    python -B -X utf8 scripts/export_portable.py
    python -B -X utf8 scripts/native_controls.py --platform both

参考解 CODESYS 批量验收可复用引擎进程；三类程序的完整闭环另有冒烟脚本：

    python -B -X utf8 scripts/codesys_reference_batch.py --adapted
    python -B -X utf8 scripts/integration_smoke.py

上述冒烟是离线模拟生成，但调用两个真实平台，并执行功能测试和限时 LTL 检查；不计作模型能力实验。

完整 LTL 检查单独执行，可能耗时数十分钟；截断和超时会如实记录：

    python -B -X utf8 -m stbench verify-refs --mc --out evidence/reference_mc_current.json

上述 matrix 中的两种 fixture 是离线测试服务；不是两种真实模型。Codex 分支实际运行本机 Codex CLI，模型端由本地 Responses 模拟服务提供固定参考代码。此结果只能证明接口和评测流水线可运行。

## 真实实验开启条件

本项目已确定的实验使用 `config.dmxapi.json` 与 `campaign` 入口，共用 `E:/PLC_Dev/evidence/dmxapi_budget_75.json`。旧 `matrix` 入口不允许绕开共享账本。凭据仅从本机 `DMXAPI_API_KEY` 读取。

    python -B -X utf8 -m stbench campaign prepare
    python -B -X utf8 -m stbench campaign probe --live
    python -B -X utf8 -m stbench campaign limit-check --live
    python -B -X utf8 -m stbench campaign pilot --live

协议探测复用已完整记录的结果；未知上游结果仍停止批次并保留费用预留。仅当已结算的身份诊断证据与账本相符时，`campaign recover-identity --evidence <诊断JSON>` 才能恢复身份校验造成的停止，且不会退回旧预留。当前接入累计上限为 8 元，开发累计仍为 20 元、正式累计 65 元、复测累计 75 元；增加的 3 元从开发阶段调出，总额与正式预留不增加。正式评测保护全部未覆盖题目的首候选预算，输出上限保持 16384 token。

当前配置指向第八版目录 `campaign_75_window_r8`；第七版已停止的目录 `campaign_75_repair_r7` 保留全部历史记录。第七版调度记录见[正式覆盖调度修复](docs/正式覆盖调度修复_20261031.md)。DeepSeek 两框架统一原生 Responses 并请求 `reasoning.effort=low`，MiniMax 两框架统一 Chat 桥接。单次生成硬时限 420 秒，整题仍为 600 秒，输出上限仍为 16384 token。`limit-check` 必须真实触达小额度截断边界并返回完整用量，其源码与配置哈希匹配后才能运行候选批次。恢复时必须使用新的输出版本，不能覆盖旧 `freeze.json` 或清空共享账本；任何新停止都不能复用不关联该次失败的旧诊断。

当前修复版的离线验收记录为 `evidence/request_window_fix_r8_20261031/validation.json`，108 项回归、七组检查和 435/435 参考用例通过；历史第七版的 100 项回归见 `evidence/repair_guard_r7_20261031/validation.json`。历史各轮证明保留在各自 evidence 目录。新验收可写入另一个尚不存在的目录：

历史第六版接续工程包 v2.2.1 已在独立目录解压，419 项文件哈希及 97 项回归通过；它是开发检查点，不是当前源码或最终四组性能交付。

接续聊天前先检查 `E:/PLC_Dev/evidence/real_experiments/campaign_75_window_r8/active_run.json` 中的进程及创建时间，确认没有已有付费流程运行后再启动。共享账本以 E 盘当前文件为准，交接包中的 budget snapshot 仅供审计，不得用来覆盖或退回当前余额。

    python -B -X utf8 scripts/validate_continuation.py --out evidence/新的版本目录

第八版启动器显式要求当前验收文件（已有实验运行时不要执行）：`python -B -X utf8 scripts/run_frozen_campaign.py --validation evidence/request_window_fix_r8_20261031/validation.json`。归档程序也要求同一 `--validation` 参数，不能再使用旧版不带参数的命令。

Codex 的 stdout/stderr 直接保存到隔离工作目录，超时后终止该次进程树，上游失败立即反馈，避免 CLI 等待重连。`recover-codex-timeout` 仅允许当前离线验证与最新故障关联的单次恢复，不增加时限或退回未知预留。旧 `create_handoff.py` 针对历史 v2.1，会覆盖旧包与历史说明；当前接续不要运行它。

以下为另行配置实验时的字段说明；本次已确定的模型无需重新选择：

复制 config.example.json 为 config.local.json。只有用户确定模型与预算后，才填写 models、budget_cny 并设置 live_enabled=true。至少配置两个已核验为不同模型的条目：

    {
      "id": "由用户指定的实验标签",
      "provider": "openai-compat 或 anthropic",
      "model": "用户指定的准确模型标识",
      "base_url": "用户指定的 HTTPS API 根路径",
      "responses_base_url": "已核验支持 Responses API 的 HTTPS 根路径",
      "api_key_env": "保存凭据的环境变量名",
      "input_cny_per_million": 由用户确认的数字,
      "output_cny_per_million": 由用户确认的数字
    }

以上仅为字段说明，不能直接当作有效 JSON 配置。密钥不写入配置或交接包。若所选模型不支持 Codex 所需协议，先调整经用户确认的基线接入方案，不得自动更换模型。

    python -B -X utf8 -m stbench matrix --config config.local.json --adapted --out runs/final/summary.json

真实实验要求可用的 CODESYS 模板。预算按最坏请求金额预留，获得实际用量后结算；失败或缺失用量的请求保留预留额。汇总中的静态检查率、真实平台编译率、功能测试率和有界验证结果分别计算。

## 目录

- stbench/harness：任务控制、精简上下文、最佳候选、停止和恢复。
- stbench/evaluation.py、judge_worker.py：独立裁判、反馈脱敏、硬超时。
- stbench/platforms.py：CODESYS 与 OpenPLC 真实平台接口。
- stbench/codex_baseline.py：实际 CLI、本地模拟和受预算控制的 Responses 网关。
- stbench/portability.py：明确记录的计数时间、类型转换与 FIFO 特化适配。
- evidence：机器可读结果和逐题记录。
- docs/成员2技术交接.md：设计与交接说明。

平台主体、安装包、大型缓存和编译目录位于 E:\PLC_Dev。交接包不包含整个 PLC 软件安装目录。

三类真实工程、正负控制和适配后的 35 题见 platform_projects。运行演示与评分项映射见 docs/评分项对应与演示.md；docs/验收报告.md 是历史 v2.1 验收；当前完成边界以第七版运行登记、冻结清单及实际阶段汇总为准。
