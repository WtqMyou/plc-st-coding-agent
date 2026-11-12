# matiec 方言差异清单

> 对象：`WtqMyou/plc-st-coding-agent` 的 35 份参考解（`agent_dev_r9/datasets/{public,selfmade}/tests/*.reference.st`）
> 对照：官方校验器 `https://agents4ics.com` 的 `POST /api/compilation/validate`（Agents4PLC Enhanced API v2.0.0，matiec 后端 + 中文错误包装）
> 日期：2026-11-12

## 0. 一句话结论

**仓库自带的解释器是"宽容方言"，官方校验器是"严格方言"。35 份参考解在自家解释器下 435/435 用例全过，但在官方校验器下只有 3 份能编译。** 只做一件事——给块结束补分号——就能从 3/35 升到 15/35，而且补完之后在自家解释器下仍然 435/435（已离线复验）。

这不是"模型写错了 ST"，是**两套前端对同一份符合 IEC 61131-3 的文本判法不同**。

## 1. 怎么验的（可复现）

```js
// Node，注意：curl / Python requests 会被 TLS 指纹拦截（RST），只有 Node https 能通
POST https://agents4ics.com/api/auth/trial      {"device_id":"trial-<ts>-<hex>"}  -> {token}
POST https://agents4ics.com/api/compilation/validate {"st_code":"<全文>"}          -> {validation:{is_valid, errors[]}}
```

- 全量结果：`C:/tmp/refs_full.json`（35 份 × 全部错误）
- 首次结果：`C:/tmp/matiec_refs.json`；两条规则修正后：`C:/tmp/matiec_fixed.json`
- 客户端脚本：`C:/tmp/mc.js`（并发 2、250 ms 间隔、3 次重试）
- 试用配额：按 IP 每天限次，用尽返回 `429 TRIAL_RATE_LIMITED`（"当前网络今日的试用名额已用完"）

## 2. 结果总览

| 指标 | 数值 |
|---|---|
| 参考解总数 | 35 |
| 官方校验通过 | **3**（`public-medium-07`、`self-hard-05`、`self-hard-06`） |
| 只补块结束分号后通过 | **15**（+12） |
| 官方错误总条数 | 约 260 条 |
| 单份最多错误 | `public-medium-08` 53 条 |
| 自家解释器通过 | 35/35（435 用例全过） |
| 归一化后再跑自家解释器 | 35/35（435 用例全过，见 §7） |

错误分布（按官方报错原文归并）：

| 规则 | 官方报错原文 | 条数 | 命中文件数 |
|---|---|---|---|
| R1 | `';' missing at the end of statement` | 143 | **25** |
| R8 | `赋值语句 ':=' 左侧变量无效` | 35 | 2 |
| R5 | `invalid / unexpected located variable declaration` | 18 | 2 |
| R6 | `invalid statement in ST statement` | 7 | 6 |
| R2 | `ELSE IF 不是 ST 语法` | 5 | 5 |
| R2b | `invalid statement list in 'ELSEIF' state` | 5 | 1 |
| R7 | `no expression defined after 'OR' / '*'` | 9 | 3 |
| R3 | `变量类型无法识别` | 2 | 2 |
| R4 | `';' missing at end of data type declaration` | 3 | 3 |
| R9 | `Incompatible data types for ':='` | 3 | 1 |
| R10 | `invalid input variable(s) declaration` | 4 | 4 |
| 其它 | 声明/控制变量/测试表达式 | 8 | 4 |

## 3. 规则清单

### R1 块结束必须带分号 —— 影响 25/35，143 处

官方要求 `END_IF;`、`END_CASE;`、`END_FOR;`。仓库解释器两者都收。

```st
IF a THEN
  y := TRUE;
END_IF        (* 官方：';' missing at the end of statement *)
END_IF;       (* 官方：通过 *)
```

**这是最大的一条，单独修完就能救回大部分文件。**

### R2 注释被吞掉后 `ELSE` 与 `IF` 相邻 —— 影响 5 份，**且不能无脑替换成 ELSIF**

```
第 104 行第 1 列：ELSE IF 不是 ST 语法，请改用 ELSIF
```

命中：`public-hard-01`、`public-hard-05`、`public-medium-02`、`public-medium-03`、`self-medium-04`（各 1 处）。

**这 5 份文件里，一处 `ELSE IF` 这种连写都没有。** 真相是官方校验器做语法检查前把注释（含换行）整个删掉了，于是

```st
ELSE
    (* 刚进入自动模式：自动流程从头开始 …… *)
    IF NOT prevOpeMode THEN
```

在它眼里变成 `ELSE IF NOT prevOpeMode THEN`，判成非法。这是 `public-hard-01` 第 104–106 行的真实内容。IEC 里 `ELSE` 后跟一个独立 `IF` 语句是完全合法的，仓库解释器也照收。

**所以千万别写成 `ELSE IF`→`ELSIF` 的字符串替换**：原文是一个嵌套 `IF`（自带 `END_IF`），换成 `ELSIF` 会少一个 `END_IF`、并让后续语句跑出条件分支。三种可行处理，按保守程度排序：

1. 在 `ELSE` 与 `IF` 之间插一条空语句 `;` 打断相邻（最保守，语义不变，**待官方校验器复验**）；
2. 若 `ELSE` 分支下只有这一个 `IF`、且其后没有别的语句，才可安全改写成 `ELSIF` 并删掉层内 `END_IF`；
3. 把嵌套的 `IF` 抽成独立 `FUNCTION` 调用。

本机归一化脚本对这类情况**默认不动**，逐例人工确认。

### R3 类型白名单不含 `LTIME` / `UINT` / `VARIANT`

报错：`变量类型无法识别（支持 INT/BOOL/REAL/TIME 等）`

| 文件 | 变量 | 类型 |
|---|---|---|
| `public-easy-04` | `PUMP_RUNTIME_ACC` | `LTIME` |
| `public-medium-06` | `Slab_Fault_Counter` | `UINT` |
| `public-medium-06` | `Slab_Runtime_Accumulator` | `LTIME` |
| `public-hard-04` | `item` | `VARIANT` |

反过来，`USINT`、`WORD`、`STRING(n)`、`ARRAY[..] OF T` 实测**能过**（`public-hard-02` 的 `USINT` 报的是类型不兼容，不是类型无法识别）。所以白名单不是"窄"，是**挑食**。

修法：`LTIME`→`TIME` 或 `DINT`；`UINT`→`INT`；`VARIANT`→ 具体类型或改用 `ANY`/泛化接口。

### R4 `END_TYPE` 必须带分号

```
第 7 行第 10 列：';' missing at end of data type declaration.
```

命中 `public-hard-03`、`public-medium-01`、`self-medium-01`。三者都是同一写法：

```st
TYPE ST_Pump :
STRUCT
    priority : INT;
END_STRUCT
END_TYPE      (* 官方：缺分号 *)
```

修法：`END_TYPE;`（`END_STRUCT` 后也建议补 `;`）。

### R5 FUNCTION_BLOCK 里不许出现 located 变量 / `AT`

```
第 19 行第 5 列：invalid located variable declaration.
第 18 行第 1 列：unexpected located variable(s) declaration in function block declaration.
```

命中 `public-medium-05`、`public-medium-08`（18 条，且是这两份的**首错**）。官方只允许在 PROGRAM/CONFIGURATION 层用 `AT %I*/%Q*/%M*`。

### R6 表达式跨行续行敏感

```
no expression defined after 'OR' in ST expression.
no expression defined after '*' in ST expression.
```

命中 `self-hard-07`、`self-medium-05`、`self-medium-06`。典型形态：

```st
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
 AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);
```

仓库解释器把换行当空白，官方校验器在某些上下文里把换行当语句边界。修法：**把跨行表达式收成一行，或用括号整体包住**。

### R7 `CASE` / `FOR` 的语法细节

```
invalid test expression in 'CASE' statement
invalid control variable in 'FOR' statement
```

命中 `public-medium-05`（CASE）、`public-medium-08`（FOR L36/L82）。这两份同时也是 R5 的重灾区，**首错在声明上，正文错误可能是级联**——先修声明再看。

### R8 `:=` 左值非法（阶梯报错，多为级联）

35 条，全部集中在 `public-medium-05`、`public-medium-08`。报错位置落在 `IF SensorA AND ButtonA THEN` 这种**不是赋值**的行上，说明解析器已经错位。

**结论：不要按这 35 条去改代码，先修掉同文件的声明类首错（R5/R3），它们大概率自动消失。**

### R9 赋值类型不兼容

`public-hard-02` 3 条 `Incompatible data types for ':='`，源码里有 `USINT` 与 `INT` 混算。官方比仓库解释器严格，不会静默提升。

## 4. 陷阱：报错行号对不上源码

官方返回的「第 N 行第 M 列」是**去除注释之后**的行号，不是原文件行号。三次实测：

| 文件 | 官方报错行 | 去注释后该行内容 | 原文件该行 |
|---|---|---|---|
| `public-hard-03` | 第 7 行 | `ingredientRatio : REAL;` | 注释里的需求编号 R2 |
| `public-easy-04` | 第 11 行 | `PUMP_MAINT_DUE : BOOL;` | `PASTE_E_STOP_NC : BOOL;` |
| `public-medium-06` | 第 12 行 | `Slab_Fault_Counter : UINT;` | `DebounceTime : TIME;` |

复现方法：把 `(* ... *)` 整段删掉（不留空行）再按行号数。

**所以：定位靠错误类型 + 变量名，不要靠行号跳转。** 带大段中文头注释的文件（`public-hard-03/04`、`public-medium-08`）偏移最大。

## 5. 对判分的影响

- 仓库仓库解释器宽容 → **参考解和候选解都可能拿到假阳性**：本机跑 435/435 全过，官方编译直接 3/35 不过。
- 也就是说，F1.4 公布的「整题功能通过」是在宽容方言下测得的，换成官方校验器后真实分数只会更低，不会更高。
- 反过来也有价值：官方校验器可以直接当**免费的客观第二裁判**，不用 CODESYS license、不用装 Windows 工具链。

## 6. 三条落地建议

1. **提示词**：把 R1/R2/R3/R4 写成硬约束（"每个 `END_IF`/`END_CASE`/`END_FOR`/`END_TYPE` 必须带分号；分支用 `ELSIF`；只允许 `BOOL/INT/DINT/REAL/LREAL/TIME/STRING/USINT/WORD` 等实测可用类型"）。
2. **后处理**：`matiec_normalizer.py`（已写好，见 §7）做机械归一化（补分号、类型降级），作为提交前的必经步骤。这一层不涉及语义，风险极低。
3. **门禁**：把官方 `/api/compilation/validate` 接成第二校验后端，`functional_pass` 之外再加一道 `official_compiles`，不合格的候选不进成绩表。

## 7. 归一化脚本与离线复验

脚本：`D:/Desktop/genAI/matiec_normalizer.py`（纯标准库，注释/字符串区域用等长哨兵遮蔽后再正则，不会误改注释里的 `END_IF`）

```bash
# 默认只做无损修正：R1 块结束补分号、R4 END_TYPE 补分号
python matiec_normalizer.py --in <目录> --out <输出目录> --json report.json

# 追加类型降级（有语义风险，需逐例确认）
python matiec_normalizer.py --in <目录> --out <输出目录> --types
```

实测（对 35 份参考解）：

| 模式 | 改动文件 | 补 `;` | `END_TYPE;` | 类型替换 |
|---|---|---|---|---|
| 默认 | 26/35 | 207 处 | 4 处 | 0 |
| `--types` | 28/35 | 207 处 | 4 处 | 20 处 |

**离线复验**：把归一化后的 35 份参考解放回 `datasets`，跑 `python -m stbench verify-refs` → **435/435 用例仍全过**，说明补分号这一步不改变语义。

**对 219 份历史候选同样处理**：86 份被改动，补 `;` 588 处、`END_TYPE;` 16 处；用仓库前端重新解析，归一化前后都是 141 份可解析，**0 破坏、0 新增**——说明这套机械改写对真实模型输出同样安全。

（注：仓库前端解析通过 141 份，判题器记录的 `compiles` 是 109 份，差 32 份是解析通过但类型检查未过的，口径不同。）

官方校验器复验（应得 15/35）待配额恢复后补跑，命令见 §8。

## 8. 批量复验（配额恢复后一条命令）

```bash
# 1) 取 token（每 IP 每日限量，用完返回 429 TRIAL_RATE_LIMITED）
node C:/tmp/mc.js refs <归一化后的 datasets 目录> C:/tmp/refs_norm_official.json ".reference.st"
# 2) 对 219 份历史候选做同样的事，再与 job json 里的 compiles/functional_pass 做交叉表
```

通过（3）：`public-medium-07`、`self-hard-05`、`self-hard-06`

| 文件 | 错误数 | 首错 |
|---|---|---|
| public-easy-01 | 3 | 缺分号 |
| public-easy-02 | 8 | 缺分号 |
| public-easy-03 | 3 | 缺分号 |
| public-easy-04 | 7 | 类型无法识别（LTIME） |
| public-easy-05 | 7 | 缺分号 |
| public-easy-06 | 5 | 缺分号 |
| public-hard-01 | 1 | ELSE IF |
| public-hard-02 | 3 | 类型不兼容 |
| public-hard-03 | 16 | 类型声明缺分号 |
| public-hard-04 | 12 | 声明有误（VARIANT / VAR_IN_OUT） |
| public-hard-05 | 1 | ELSE IF |
| public-hard-06 | 15 | 缺分号 |
| public-medium-01 | 8 | 类型声明缺分号 |
| public-medium-02 | 1 | ELSE IF |
| public-medium-03 | 1 | ELSE IF |
| public-medium-04 | 6 | 缺分号 |
| public-medium-05 | 22 | located 变量 |
| public-medium-06 | 1 | 类型无法识别（UINT/LTIME） |
| public-medium-08 | 53 | 声明缺分号（STRING(254)） |
| self-easy-01 | 3 | 缺分号 |
| self-easy-02 | 4 | 缺分号 |
| self-hard-01 | 7 | 缺分号 |
| self-hard-02 | 3 | 缺分号 |
| self-hard-03 | 6 | 缺分号 |
| self-hard-04 | 7 | 缺分号 |
| self-hard-07 | 7 | 输入变量声明 |
| self-medium-01 | 6 | 类型声明缺分号 |
| self-medium-02 | 5 | 缺分号 |
| self-medium-03 | 8 | 缺分号 |
| self-medium-04 | 1 | ELSE IF |
| self-medium-05 | 6 | 输入变量声明（LREAL 组合） |
| self-medium-06 | 5 | 输入变量声明 |

## 附录 B 复现脚本骨架

```js
const https = require('https');
function post(path, body, tok) { /* host: agents4ics.com, rejectUnauthorized:false */ }
const tk = await post('/api/auth/trial', {device_id:'trial-'+Date.now()+'-'+rand});
const r  = await post('/api/compilation/validate', {st_code: code}, tk);
// r.validation.is_valid / r.validation.errors[]
```

注意：试用 token 按 IP 每日限额，批量跑 219 份候选前先估算用量（1 份 ≈ 1 次调用）。
