# CHANGELOG v1.1 → v1.2（2026-10-27）

> 一句话：**自建题 10 → 15 道，用例 77 → 134 条，LTL 规约 44 → 79 条**；
> 引擎只改了 1 行（十六进制字面量），其余全是数据与文档；
> 顺带修掉 6 份与代码漂移的参考解文件，并让模型检查第一次覆盖全部 15 道题。

---

## 1. 数字对照

| 项目 | v1.1（10-26） | v1.2（10-27） | 变化 |
| --- | --- | --- | --- |
| 公共题 | 20 道 | 20 道 | — |
| 公共题用例 | 301 | 301 | — |
| 公共题规约 | 114（LTL 96） | 114（LTL 96） | — |
| **自建题** | **10 道** | **15 道** | **+5** |
| **自建题用例** | **77** | **134** | **+57** |
| **自建题规约** | **49（LTL 44 + simulation 5）** | **89（LTL 79 + simulation 10）** | **+40（LTL +35）** |
| 合计用例 | 378 | **435** | +57 |
| 合计规约 | 163 | **203** | +40 |
| 参考解 `.reference.st` 文件 | 10 份（其中 6 份与代码不一致） | **15 份（全部由代码导出，一致）** | 修 6 + 增 5 |
| 模型检查覆盖 | 10 道题 / 44 条 LTL | **15 道题 / 79 条 LTL** | +5 题 / +35 条 |

> **75 / 77 / 134 三个数字的来源**：75 是 10-24 18:50 那份《成员1实操手册》里的旧统计（当时用例表还在改动）；
> v1.1 包内实际是 77；v1.2 新增 5 道题 57 条用例 = 134。
> 现在 `datasets/selfmade/_index.json` 由脚本生成，是这个数字的唯一真源，不再手写。

---

## 2. 新增的 5 道自建题

| 题号 | 难度 | 标题 | 来源 | LTL | 用例 |
| --- | --- | --- | --- | --- | --- |
| self-hard-05 | hard | 燃烧状态与氧量修正联锁（熄火跳闸 + 分析仪故障降级） | 队友草案 P01 ← 2026 CIMC 初赛燃烧控制环节 | 9 | 13 |
| self-medium-05 | medium | 合格蒸汽产量与净收益累计（闭区间判定 + 数据故障冻结） | 队友草案 P02 ← 锅炉产汽计量/能耗核算 | 7 | 11 |
| self-medium-06 | medium | 温度模糊控制与输出钳位（重心法 + 历史误差清除） | 队友草案 P03 ← 温控模糊修正改造 | 5 | 10 |
| self-hard-06 | hard | 蒸汽母管超压联锁与故障线索诊断（按位编码 + 足迹保留） | 队友草案 P04 ← 2026 CIMC 初赛超压联锁题 | 8 | 10 |
| self-hard-07 | hard | 串级 PI 手自动无扰切换（积分预置 + 切换拍保持） | 队友草案 P05 ← 串级控制无扰切换 | 6 | 13 |

对队友草案做的**实质改动**（评审结论见 `五题评审结论与替换方案.md`）：

1. **派生谓词全部显式化**：原草案在规约里用 `inAuto`、`o2TrimRaw`、`tripCause1/2/3`、`totalFlow`
   这类**接口里没有、程序里也没定义**的名字写 LTL——这类规约永远判不了（求值器只能报错或恒真）。
   现在要么改成真正的接口变量（如 `o2Fault`、`qualified`、`dataFault`），要么把判据直接写进规约正文。
2. **位掩码代替三个布尔线索位**：self-hard-06 用 `currentCauseMask / latchedCauseMask`（INT 位掩码）
   表达「为什么跳闸」，规约里用十进制断言（2/4/6/8/12/14/5），可直接判定。
3. **新增输出 `normalMode`**：self-hard-07 原草案只有 3 个输出，无法表达「切换拍」这一时序性质；
   加 `normalMode`（本拍是否正常运算）后，两条无扰切换性质（S3/S4）才第一次变得可判定。
4. **`rising()/falling()/prev()` 边沿算子**：用于「上升沿才清零 / 开关量跳变」这类性质，
   避免了「自己造一个 hasPrev 变量」导致规约跟实现耦合。

---

## 3. 引擎改动（只有 1 行）

| 文件 | 改动 | 为什么 |
| --- | --- | --- |
| `stbench/ltl.py` | 词法正则增加十六进制字面量 `16#XXXX` | 故障位掩码题（self-hard-05/06）的规约里出现 `16#0008` 这类常量，不加就整条规约解析失败 |

其余核心文件（`st/frontend.py`、`st/typecheck.py`、`st/interp.py`、`modelcheck.py`）**未改动**——
新增 5 道题全部用的都是既有语法子集，没有为新题放宽语义。

---

## 4. 数据修正（v1.1 遗留问题）

### 4.1 6 份参考解文件与代码不一致

v1.1 里 `datasets/selfmade/tests/*.reference.st` 是手工放进去的快照，与 `selfmade_refs.py` 里的
`REFS` 字符串已经漂移（题目改过用例、参考解跟着改，但文件没重新导出）。
v1.2 新增 `tools/export_references.py`，从代码**单向导出**全部 15 份，彻底消除两处维护。

| 文件 | 变化 |
| --- | --- |
| `self-easy-02.reference.st` | 43 → 55 行（+18/-6） |
| `self-hard-01.reference.st` | 35 → 37 行（+3/-1） |
| `self-hard-02.reference.st` | 40 → 42 行（+3/-1） |
| `self-medium-01.reference.st` | 51 → 53 行（+3/-1） |
| `self-medium-03.reference.st` | 72 → 79 行（+19/-12） |
| `self-medium-04.reference.st` | 59 → 63 行（+6/-2） |

### 4.2 索引重建

`datasets/selfmade/_index.json`：10 条 → **15 条**，并新增两个字段：
`n_ltl`（这题有几条真正可判定的 LTL）与 `case_mode`（single / sequence）。
原来的 `n_specs` 把 simulation-only 的规约也算进去，看不出「有几条是真的能被机器判定的」。

### 4.3 self-hard-04 的 `rotated` 方向标错（v1.1 已修，此处记录）

原标 `OUTD`（输出「本周期发生切换」），但用例按输入传、参考解按 `VAR_INPUT` 读——
三处自相矛盾而编译器不报错（因为它只报类型，不报语义方向）。
现改为输入变量「轮换请求」，题面第 5 条与 S3 描述同步。

---

## 5. 参考解第一次被模型检查"反查"

v1.2 跑全量模型检查时，**self-medium-06（温度模糊控制）被抓到一个真 bug**：

```
S3: G((!enable | rising(resetBtn) | fault) -> (power = 0.0 & correction = 0.0))
反例：第 1 拍，resetBtn 上升沿，bias=50 → correction=0 但 power=50
```

原因：参考解在「禁用/故障」分支把 `power` 置零，但**漏了 reset 上升沿这一支**——
`correction` 归零了，`power` 还等于 `bias`。
修法：把边沿判定提前成一个静态布尔 `edgeReset`，让 `correction` 与 `power` 用**同一个条件**。
修完后 self-medium-06 的 5 条 LTL 全部 hold。

> 这件事本身就是论文素材：**用例测试没抓到（10/10 全过），模型检查抓到了**——
> 因为用例只覆盖了「你想到的那几拍」，而模型检查枚举了所有可达状态。

### 5.1 另两条 LTL 写法缺陷（模型检查报了「界内无法判定」）

self-medium-05 的 S5 在模型检查里报 `LTL 解析失败：括号不配对`，追下去发现是**语法能力边界**：

```
G((prev(fuelTon) > 0.0 & ...) -> fuelTon = prev(fuelTon))   ← 解析失败
```

当前 LTL 语法里，比较运算只能出现在「原子」内部（`x > 0.0`），
**`prev(...)` / `rising(...)` 不能出现在比较运算符左边**。两种处理：

- 改写成语法允许的等价形式（本次采用）：
  `G((!rising(resetBtn) & (!enable | dataFault)) -> fuelTon = prev(fuelTon))`
- 或者改语法（要动求值器的值语义，风险大，v1.3 再说）。

另外扫全量 175 条 LTL 时，还发现公共题 `public-easy-02` 的 S6 同样是这个写法，
已同步改成 `G((value <> prev(value)) -> hasChanged)`。现在全库 0 条可疑。

---

## 6. 新增文件清单

### 数据

```
+ datasets/selfmade/self-hard-05.json
+ datasets/selfmade/self-hard-06.json
+ datasets/selfmade/self-hard-07.json
+ datasets/selfmade/self-medium-05.json
+ datasets/selfmade/self-medium-06.json
+ datasets/selfmade/tests/self-hard-05.reference.st
+ datasets/selfmade/tests/self-hard-06.reference.st
+ datasets/selfmade/tests/self-hard-07.reference.st
+ datasets/selfmade/tests/self-medium-05.reference.st
+ datasets/selfmade/tests/self-medium-06.reference.st
+ datasets/selfmade_new5.py            # 新 5 题的生成脚本（单一真源）
+ datasets/_source/大作业题库.json      # 原始题库备份（v1.1 有、源码树丢了，已恢复）
```

### 代码

```
+ stbench/selfmade_new5_refs.py        # 新 5 题的参考解（含 10 条改写过的 LTL）
+ tools/export_references.py           # 从 REFS 单向导出 15 份 .reference.st + 重建索引
+ tools/_t_mc_all.py                   # 全量模型检查（带路径修正，放进包内可直接跑）
+ tools/_t_new5_dump.py                # 单题逐拍变量 dump（调参考解时最有用）
+ tools/_count.py                      # 数据集统计
+ tools/diff_v11_v12.py                # 与旧包做文件级差异比对
```

### 改动

```
M datasets/selfmade/_index.json              82 → 152 行
M datasets/selfmade/tests/self-easy-02.reference.st     43 → 55 行
M datasets/selfmade/tests/self-hard-01.reference.st     35 → 37 行
M datasets/selfmade/tests/self-hard-02.reference.st     40 → 42 行
M datasets/selfmade/tests/self-medium-01.reference.st   51 → 53 行
M datasets/selfmade/tests/self-medium-03.reference.st   72 → 79 行
M datasets/selfmade/tests/self-medium-04.reference.st   59 → 63 行
M stbench/ltl.py                             691 → 691 行（+1/-1：十六进制字面量）
M stbench/selfmade_refs.py                   710 → 716 行（+6：import 新 5 题参考解）
```

---

## 7. 验收结果（全部在交付包内重跑，日志见 `验收证据/`）

| # | 命令 | 期望 | v1.1 | v1.2 |
| --- | --- | --- | --- | --- |
| 01 | `tests/test_verifier.py` | 全绿 | 15/15 + 5/5 | 见 `01_编译器与仿真器回归.log` |
| 02 | `tests/test_harness.py` | 9/9 | 9/9 | 见 `02_Agent回路回归.log` |
| 03 | `stbench.selfmade_refs` | 15/15 题 | 10/10 题 77/77 | 见 `03_自建题参考解.log` |
| 04 | `check_dataset.py --selfmade` | 15/15 | 10/10 | 见 `04_数据集体检.log` |
| 05 | `verify_one.py <public-pid> --no-mc` ×20 | 20/20 编译通过 | 20/20 | 见 `05_公共题20参考解.log` |
| 06 | `tools/_t_mc_all.py` | 79 条 LTL 全 hold | 44 条全 hold | **79 条 hold=79 viol=0 incon=0**（614 s） |

**06 的关键读法**（不要误读）：
- `hold=79 viol=0` 指「在深度 8、每题 6 万次迁移预算内未发现违反」。
- 其中 **9 道题的 `traces` 撞到 60000 上限**，报告会标 `truncated=True` —— 这些题的结论只能写成
  「预算内未发现违反」，**不能**写成「已证明」。
- 另有 10 条规约是 `verified_by: simulation`（下标访问等 LTL 判不了的性质），不计入 79。

---

## 8. 仍然没做的事（如实）

1. **没在真实 PLC / CODESYS 上编译过**。全部结论都在自研解释器的语义下成立。
2. **没有符号模型检查**（无 NuSMV/nuXmv 接入），是有界穷举。
3. 公共题 20 道虽然都能编译、能用参考解跑通，但**没有为它们写 LTL 规约**（只有公共题原文）。
4. 新 5 题目前只有参考解 + 用例 + LTL，**还没有跑过 LLM 生成实验**（下一阶段由实验负责人接手）。

---

## 9. 复现 v1.2

```bash
cd stbench
python -X utf8 datasets/selfmade_build.py      # 前 10 道
python -X utf8 datasets/selfmade_new5.py       # 后 5 道
python -X utf8 tools/export_references.py      # 15 份参考解 + 索引
python -X utf8 -m stbench.selfmade_refs        # 期望 15/15 题、134/134 用例
python -X utf8 scripts/check_dataset.py --selfmade   # 期望 15/15
python -X utf8 tools/_t_mc_all.py             # 期望 79 条 LTL 全 hold（约 12 分钟）
```
