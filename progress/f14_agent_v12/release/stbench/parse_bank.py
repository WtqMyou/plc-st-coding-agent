"""把原始题库（中英混杂的 Markdown）解析成结构化 Problem。

为什么需要解析器而不是手工录入
------------------------------
公共题共 20 道、每道都有接口表。手抄进 JSON 一定会错（类型写错、方向写反），
而接口表恰恰是编译检查与仿真测试的唯一依据。所以写解析器：**一次性对齐格式，
之后每次都以解析结果为准**，并且可以把解析结果和原文一起落盘做人工复核。

格式约定（从题库实测归纳）
--------------------------
::

    # <Title>
    - **Difficulty:** Hard (h)              <- 英文
    - **难度:** 困难 (h)                     <- 中文
    ## Requirements / ## 需求
    ## Interface Definition / ## 接口定义
    | Variable | Direction | Data Type | Description |
    | `Name` | Input | `BOOL` | ... |
    | `Arr` | Input | `ARRAY[1..5] OF ST_Pump` | ... |
    | `Flag` | Output | `BOOL` | ... |
    | `P` | Input/Output | `ST_Profile` | ... |

    **Data type ST_Pump**
    | Field | Data Type | Description |
    | `id` | `INT` | ... |

解析器的立场：**宁可报错，不要猜**。接口表任何一行解析不出来就直接抛异常，
让人回头看原文，而不是带着一个错误的类型一路跑到仿真阶段才暴露。
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from .schema import Difficulty, Direction, Problem, VarDef

# 中文/英文表头都接受；题库里英文占多数，中文题也许会出现
_HEADER_DIFF_EN = re.compile(r"\*\*Difficulty:\*\*\s*(\w+)", re.I)
_HEADER_DIFF_ZH = re.compile(r"\*\*难度:\*\*\s*(\S+)")
_REQ_EN = re.compile(r"^##\s+Requirements\s*$", re.M)
_REQ_ZH = re.compile(r"^##\s*需求\s*$", re.M)
_IFACE_EN = re.compile(r"^##\s+Interface Definition\s*$", re.M)
_IFACE_ZH = re.compile(r"^##\s*接口定义\s*$", re.M)
_STRUCT_HEADER = re.compile(r"^\*\*Data type\s+`?(\w+)`?\*\*\s*$", re.M)

_DIFF_MAP = {
    "easy": Difficulty.EASY,
    "简单": Difficulty.EASY,
    "medium": Difficulty.MEDIUM,
    "中等": Difficulty.MEDIUM,
    "hard": Difficulty.HARD,
    "困难": Difficulty.HARD,
}

# "Input/Output" 在题库里表示引用传递：调用方读写同一个结构体
_DIR_MAP = {
    "input": Direction.INPUT,
    "输入": Direction.INPUT,
    "output": Direction.OUTPUT,
    "输出": Direction.OUTPUT,
    "input/output": Direction.INOUT,
    "输入/输出": Direction.INOUT,
    "inout": Direction.INOUT,
}

# 结构体单字段行：Direction 列写 "Input field" / "Output field"，
# 粒度比 Input/Output 更细（同一个结构体里有的字段只读、有的可写）。
# 我们把它归一化成 INOUT 的分组上下文，字段级可写性另存。
_FIELD_DIR_MAP = {
    "input field": Direction.INPUT,
    "output field": Direction.OUTPUT,
    "输入字段": Direction.INPUT,
    "输出字段": Direction.OUTPUT,
}


def _split_row(line: str) -> list[str]:
    """按 | 切表格行，并去掉反引号与首尾空白。"""
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    return [c.strip("`").strip() for c in cells]


def _is_separator(line: str) -> bool:
    return bool(re.fullmatch(r"\|[\s:|-]+\|", line.strip()))


def _parse_tables(text: str) -> list[tuple[list[str], list[list[str]]]]:
    """抽出所有 Markdown 表格，返回 [(表头, 数据行)]。"""
    tables: list[tuple[list[str], list[list[str]]]] = []
    buf: list[str] = []
    for line in text.splitlines():
        if line.strip().startswith("|"):
            buf.append(line)
        else:
            if buf:
                tables.append(_parse_one_table(buf))
                buf = []
    if buf:
        tables.append(_parse_one_table(buf))
    return tables


def _parse_one_table(lines: list[str]) -> tuple[list[str], list[list[str]]]:
    rows = [ln for ln in lines if not _is_separator(ln)]
    header = _split_row(rows[0])
    body = [_split_row(ln) for ln in rows[1:]]
    return header, body


def _col_index(header: list[str], *candidates: str) -> int | None:
    """按名字模糊找列，兼容中英表头。"""
    for i, h in enumerate(header):
        low = h.lower()
        for cand in candidates:
            if cand.lower() in low:
                return i
    return None


def parse_problem(text: str, pid: str, source: str) -> Problem:
    """把一段题库 Markdown 解析成 Problem。解析失败直接抛出 ValueError。"""

    # ---- 标题 & 难度 ----
    title_m = re.search(r"^#\s+(.+)$", text, re.M)
    if not title_m:
        raise ValueError(f"{pid}: 找不到标题")
    title = title_m.group(1).strip()

    diff_m = _HEADER_DIFF_EN.search(text) or _HEADER_DIFF_ZH.search(text)
    if not diff_m:
        raise ValueError(f"{pid}: 找不到难度标记")
    raw_diff = diff_m.group(1).strip().lower().rstrip("（")
    difficulty = _DIFF_MAP.get(raw_diff)
    if difficulty is None:
        raise ValueError(f"{pid}: 未知难度 {raw_diff!r}")

    # ---- 需求正文：Requirements 到 Interface Definition 之间 ----
    req_start = _REQ_EN.search(text) or _REQ_ZH.search(text)
    iface_start = _IFACE_EN.search(text) or _IFACE_ZH.search(text)
    if not req_start:
        raise ValueError(f"{pid}: 找不到 Requirements 段")
    req_end = iface_start.start() if iface_start else len(text)
    requirements = text[req_start.end() : req_end].strip()

    # 语言判定：需求正文里出现中文字符即视为中文题
    language = "zh" if re.search(r"[\u4e00-\u9fff]", requirements) else "en"

    # ---- 接口表 ----
    variables: list[VarDef] = []
    if iface_start:
        iface_text = text[iface_start.end() :]
        tables = _parse_tables(iface_text)
        if not tables:
            raise ValueError(f"{pid}: 有接口段落但没有表格")
        header, body = tables[0]
        i_name = _col_index(header, "variable", "变量")
        i_dir = _col_index(header, "direction", "方向")
        i_type = _col_index(header, "data type", "type", "类型")
        i_desc = _col_index(header, "description", "说明", "描述")
        if i_name is None or i_dir is None or i_type is None:
            raise ValueError(f"{pid}: 接口表缺列，表头={header}")
        for row in body:
            if len(row) <= max(i_name, i_dir, i_type):
                continue
            var_name = row[i_name].strip()
            raw_dir = row[i_dir].strip().lower()

            # 结构体字段行："channels[].retVal" 这类名字带 "[]." 的，
            # 描述的是元素字段而不是独立参数，只用来补字段可写性。
            if "[]." in var_name:
                base = var_name.split("[].")[0]
                field = var_name.split("[].")[1]
                fdir = _FIELD_DIR_MAP.get(raw_dir)
                if fdir is not None:
                    for v in variables:
                        if v.name == base and v.fields:
                            for f in v.fields:
                                if f.name == field:
                                    f.direction = fdir
                continue

            direction = _DIR_MAP.get(raw_dir)
            if direction is None:
                raise ValueError(f"{pid}: 未知方向 {row[i_dir]!r}（变量 {var_name}）")
            variables.append(
                VarDef(
                    name=var_name,
                    data_type=row[i_type],
                    description=row[i_desc] if i_desc is not None and i_desc < len(row) else "",
                    direction=direction,
                )
            )

        # ---- 结构体字段表 ----
        # 两种写法都要支持：
        #   A) 独立的 "**Data type ST_X**" 段落 + 一张 Field 表（多数题的写法）
        #   B) 接口表里直接给 "RunComd" / "BOOL" 这种 变量/类型 两列（局部片段）
        # B 类片段会污染接口表，必须先剔除再处理 A 类。
        for m in _STRUCT_HEADER.finditer(iface_text):
            st_name = m.group(1)
            tail = iface_text[m.end() :]
            sub_tables = _parse_tables(tail)
            if not sub_tables:
                continue
            s_header, s_body = sub_tables[0]
            f_name = _col_index(s_header, "field", "字段", "变量")
            f_type = _col_index(s_header, "data type", "type", "类型")
            f_desc = _col_index(s_header, "description", "说明", "描述")
            if f_name is None or f_type is None:
                continue
            fields = [
                VarDef(
                    name=r[f_name],
                    data_type=r[f_type],
                    description=r[f_desc] if f_desc is not None and f_desc < len(r) else "",
                    direction=Direction.INOUT,
                )
                for r in s_body
                if len(r) > max(f_name, f_type) and r[f_name] not in ("Variable", "Field")
            ]
            for v in variables:
                if v.data_type == st_name or v.data_type.endswith(f" {st_name}"):
                    v.fields = fields

    # ---- 剔除"局部片段"式伪变量 ----
    # 题库里有若干题把结构体定义拆成两张表，第二张表的列名是变量名/类型，
    # 解析时会生成 name 像 "RunComd"、data_type 是 "BOOL" 的正常 VarDef，
    # 但它们并不是接口参数。判据：题目正文里没有以该名字作为接口表一行的
    # 唯一依据——这里改用更稳的判据：这类伪变量的 description 为空，
    # 且它们的名字全部出现在某个真实结构体变量的字段列表里。
    all_field_names: set[str] = set()
    for v in variables:
        for f in v.fields:
            all_field_names.add(f.name)
    real_names = {
        ln.split("`")[1]
        for ln in (iface_start and text[iface_start.end() :] or "").splitlines()
        if ln.strip().startswith("| `") and ln.count("`") >= 2
    }
    variables = [
        v for v in variables if v.name in real_names or v.name not in all_field_names
    ]

    # 同一结构体可能被多个数组变量引用，按 data_type 里的名字回填
    st_map = {v.data_type: v.fields for v in variables if v.fields}
    for v in variables:
        if v.fields:
            continue
        for st_name, fields in st_map.items():
            if st_name and st_name in v.data_type:
                v.fields = fields
                break

    # ---- 内联字段表（没有 **Data type** 段落时）----
    # medium-02 这类题的写法是：接口表里先给 ARRAY[*] OF ST_AnalogChannel，
    # 再追加若干行 Direction="Input field"/"Output field"、名字写成
    # "channels[].enable"。这些行不构成独立参数，只有把它们挂回数组元素，
    # 生成的代码才知道 ST_AnalogChannel 里有哪些字段可以写。
    if not any(v.fields for v in variables):
        arrays = [v for v in variables if "ARRAY" in v.data_type and " OF " in v.data_type]
        # 从 data_type 推断结构体名："ARRAY[*] OF ST_AnalogChannel" -> ST_AnalogChannel
        st_types: dict[str, VarDef] = {}
        for arr in arrays:
            st_types.setdefault(arr.data_type.split(" OF ", 1)[1].strip(), arr)
        for m in re.finditer(r"^\|\s*(Input field|Output field|输入字段|输出字段)\s*\|\s*`(\w+)\[\]\.(\w+)`\s*\|\s*`([^`]+)`\s*\|\s*(.*?)\s*$", iface_text, re.M):
            raw_dir, base, field, ftype, fdesc = m.groups()
            for arr in arrays:
                if arr.name != base:
                    continue
                st_name = arr.data_type.split(" OF ", 1)[1].strip() if " OF " in arr.data_type else base
                holder = st_types.get(st_name, arr)
                holder.fields.append(
                    VarDef(
                        name=field,
                        data_type=ftype,
                        description=fdesc,
                        direction=_FIELD_DIR_MAP.get(raw_dir.lower(), Direction.INOUT),
                    )
                )
        for arr in arrays:
            st_name = arr.data_type.split(" OF ", 1)[1].strip() if " OF " in arr.data_type else ""
            if st_name in st_types:
                arr.fields = st_types[st_name].fields

    return Problem(
        pid=pid,
        source=source,
        difficulty=difficulty,
        title=title,
        requirements=requirements,
        variables=variables,
        language=language,
        raw_text=text,
    )


def parse_bank(bank_path: Path, source: str = "public") -> list[Problem]:
    """解析整个题库文件，按 难度 → 出现顺序 生成 pid。

    pid 一旦生成就被后续所有产物引用（运行目录、结果 CSV、报告表格），
    所以这里保证**顺序稳定**：难度顺序固定 easy/medium/hard。
    """
    data = json.loads(bank_path.read_text(encoding="utf-8"))
    problems: list[Problem] = []
    for diff_key in ("easy", "medium", "hard"):
        for idx, item in enumerate(data.get(diff_key, []), start=1):
            text = item.get("en") or item.get("zh") or next(
                (v for v in item.values() if v), ""
            )
            pid = f"{source}-{diff_key}-{idx:02d}"
            problems.append(parse_problem(text, pid=pid, source=source))
    return problems


def export_all(problems: list[Problem], out_dir: Path) -> None:
    """每道题存一个 JSON，另存一份清单便于快速浏览。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    index = []
    for p in problems:
        p.save(out_dir / f"{p.pid}.json")
        index.append(
            {
                "pid": p.pid,
                "difficulty": p.difficulty.value,
                "title": p.title,
                "n_vars": len(p.variables),
                "n_struct": sum(1 for v in p.variables if v.fields),
                "language": p.language,
            }
        )
    (out_dir / "_index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8"
    )


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="解析公共题库为结构化 JSON")
    ap.add_argument(
        "--bank",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "大作业题库.json",
        help="原始题库 JSON 路径",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "datasets" / "public",
    )
    args = ap.parse_args()

    problems = parse_bank(args.bank)
    export_all(problems, args.out)
    print(f"解析完成：{len(problems)} 道题 -> {args.out}")
    for p in problems:
        st = [v.data_type for v in p.variables if v.fields]
        print(
            f"  {p.pid:<16} {p.difficulty.value:<6} "
            f"变量{len(p.variables):>2}  结构体{len(st)}  {p.title[:52]}"
        )
