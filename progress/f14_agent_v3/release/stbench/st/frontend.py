"""ST 源码前端：词法、语法、类型检查（"编译代理"）。

为什么需要自己写"编译器"
------------------------
作业要求"自动化编译验证"，但 CODESYS / TwinCAT 是商业授权、装不到无头服务器上，
批量跑 120 次实验时也没法让 IDE 对每份代码逐个人工点编译。
所以这里实现一个**面向 IEC 61131-3 Structured Text 子集的静态检查器**：

* 它能抓到 LLM 生成 ST 时最常犯的错——拼错变量名、漏声明、类型不匹配、
  条件里的类型错误、缺 END_IF、数组越界常量、给 INPUT 赋值；
* 它**不能**替代真实编译器（不生成代码、不报出真实的实现限制）。

报告里必须如实写清楚这条边界，这是诚实性要求；同时要说明它为什么仍然
是一个合理的验证代理：这些错误恰好是 LLM 代码失败的主因。

层次
----
``tokenize``  → 词法（关键字/标识符/字面量/运算符/注释）
``Parser``    → 递归下降，产出 AST；语法错误带行号
``typecheck`` → 名称解析 + 类型推导，产出诊断列表

诊断用 ``Diag`` 表示，级别 error/warning。error 会让"首次编译成功率"记 0。
"""

from __future__ import annotations

import re
from decimal import Decimal
from dataclasses import dataclass, field
from typing import Any

# --------------------------------------------------------------------------
# 诊断
# --------------------------------------------------------------------------


@dataclass
class Diag:
    level: str  # "error" | "warning"
    line: int
    code: str  # 稳定的错误码，便于统计"哪类错误最多"
    message: str

    def to_dict(self) -> dict[str, Any]:
        return {"level": self.level, "line": self.line, "code": self.code, "message": self.message}

    def __str__(self) -> str:
        return f"{self.level}[{self.code}] 第{self.line}行: {self.message}"


# --------------------------------------------------------------------------
# 词法
# --------------------------------------------------------------------------

KEYWORDS = {
    "IF", "THEN", "ELSIF", "ELSE", "END_IF",
    "CASE", "OF", "END_CASE",
    "FOR", "TO", "BY", "DO", "END_FOR",
    "WHILE", "END_WHILE",
    "REPEAT", "UNTIL", "END_REPEAT",
    "EXIT", "RETURN", "CONTINUE",
    "AND", "OR", "XOR", "NOT", "MOD",
    # 移位/循环移位是 IEC 61131-3 的中缀运算符。漏登记会导致词法器把
    # "x SHR i" 里的 SHR 当成标识符，解析器随后在 "期望 ')'" 处报错，
    # 表现为"位操作语法不支持"。
    "SHL", "SHR", "ROL", "ROR",
    "TRUE", "FALSE",
    "FUNCTION_BLOCK", "FUNCTION", "PROGRAM", "END_FUNCTION_BLOCK",
    "END_FUNCTION", "END_PROGRAM", "VAR", "VAR_INPUT", "VAR_OUTPUT",
    "VAR_IN_OUT", "VAR_INST", "VAR_TEMP", "VAR_GLOBAL", "END_VAR",
    "CONSTANT", "RETAIN", "PERSISTENT", "R_EDGE", "F_EDGE",
    "STRUCT", "END_STRUCT", "TYPE", "END_TYPE", "ARRAY",
    "OF", "AT", "METHOD", "END_METHOD", "THIS",
}

# 元素类型 -> 类别，用于类型检查的粗粒度比较
ELEMENTARY = {
    "BOOL": "bool",
    "BYTE": "int", "WORD": "int", "DWORD": "int", "LWORD": "int",
    "SINT": "int", "INT": "int", "DINT": "int", "LINT": "int",
    "USINT": "int", "UINT": "int", "UDINT": "int", "ULINT": "int",
    "REAL": "real", "LREAL": "real",
    "TIME": "time", "LTIME": "time",
    "STRING": "string", "WSTRING": "string",
    "CHAR": "char", "WCHAR": "char",
    "ANY": "any",
}

# 标准函数：名字 -> (返回类别, 最少参数, 最多参数)
STD_FUNCS: dict[str, tuple[str, int, int]] = {
    "ABS": ("any", 1, 1), "MIN": ("any", 2, 16), "MAX": ("any", 2, 16),
    "LIMIT": ("any", 3, 3), "SEL": ("any", 3, 3), "MUX": ("any", 2, 16),
    "MOD": ("int", 2, 2), "ADD": ("any", 2, 16), "SUB": ("any", 2, 2),
    "MUL": ("any", 2, 16), "DIV": ("any", 2, 2),
    "SHL": ("int", 2, 2), "SHR": ("int", 2, 2), "ROL": ("int", 2, 2), "ROR": ("int", 2, 2),
    "AND": ("any", 2, 16), "OR": ("any", 2, 16), "XOR": ("any", 2, 16), "NOT": ("any", 1, 1),
    "SQRT": ("real", 1, 1), "LN": ("real", 1, 1), "LOG": ("real", 1, 1),
    "EXP": ("real", 1, 1), "EXPT": ("real", 2, 2),
    "SIN": ("real", 1, 1), "COS": ("real", 1, 1), "TAN": ("real", 1, 1),
    "ASIN": ("real", 1, 1), "ACOS": ("real", 1, 1), "ATAN": ("real", 1, 1),
    "TRUNC": ("int", 1, 1), "ROUND": ("int", 1, 1), "FLOOR": ("int", 1, 1),
    "CEIL": ("int", 1, 1), "REAL_TO_INT": ("int", 1, 1),
    "INT_TO_REAL": ("real", 1, 1), "DINT_TO_REAL": ("real", 1, 1),
    "REAL_TO_DINT": ("int", 1, 1), "INT_TO_DINT": ("int", 1, 1),
    "DINT_TO_INT": ("int", 1, 1), "INT_TO_WORD": ("int", 1, 1),
    "USINT_TO_INT": ("int", 1, 1),
    "INT_TO_UDINT": ("int", 1, 1),
    "WORD_TO_INT": ("int", 1, 1), "BOOL_TO_INT": ("int", 1, 1),
    "INT_TO_BOOL": ("bool", 1, 1), "BOOL_TO_WORD": ("int", 1, 1),
    "WORD_TO_BOOL": ("bool", 1, 1), "LOWER_BOUND": ("int", 2, 2),
    "UPPER_BOUND": ("int", 2, 2),
    # ---- IEC 61131-3 字符串标准库 ----
    # 之前整个字符串函数族都缺失，导致需要解析文本的题目（IPv4 点分十进制）
    # 根本无法实现。下标 S[i]、子串 S[lo..hi] 由 index 节点单独处理。
    "LEN": ("int", 1, 1), "CONCAT": ("string", 2, 255),
    "LEFT": ("string", 2, 2), "RIGHT": ("string", 2, 2),
    "MID": ("string", 2, 3), "FIND": ("int", 2, 2),
    "INSERT": ("string", 2, 3), "DELETE": ("string", 2, 3),
    "REPLACE": ("string", 3, 4), "TRIM": ("string", 1, 1),
    "STRING_TO_INT": ("int", 1, 1), "STRING_TO_REAL": ("real", 1, 1),
    "INT_TO_STRING": ("string", 1, 1), "REAL_TO_STRING": ("string", 1, 1),
}


@dataclass
class Tok:
    kind: str  # kw | id | num | str | op | eof
    value: str
    line: int
    col: int = 0
    # 数值字面量的解析结果，避免重复解析
    num: float | int | None = None
    is_real: bool = False
    literal_type: str | None = None

    def __repr__(self) -> str:  # 便于调试
        return f"Tok({self.kind},{self.value!r},L{self.line})"


_NUM_RE = re.compile(
    r"""
    (?P<base>16\#[0-9A-Fa-f_]+|8\#[0-7_]+|2\#[01_]+)   # 基数字面量
  | (?P<real>\d[\d_]*\.\d[\d_]*(?:[eE][+-]?\d+)?|\d[\d_]*[eE][+-]?\d+) # 实数字面量
  | (?P<int>\d[\d_]*)                                # 整数字面量
    """,
    re.VERBOSE,
)
_ID_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_TYPED_PREFIX_RE = re.compile(r"(BOOL|BYTE|WORD|DWORD|LWORD|SINT|INT|DINT|LINT|USINT|UINT|UDINT|ULINT|REAL|LREAL)#",re.I)
_INTEGER_BITS = {'BYTE':8,'WORD':16,'DWORD':32,'LWORD':64,'SINT':8,'INT':16,'DINT':32,'LINT':64,
                 'USINT':8,'UINT':16,'UDINT':32,'ULINT':64}
_TIME_RE = re.compile(r"(?:LTIME|LT|TIME|T)\#-?[\dA-Za-z_.]+", re.I)
_DURATION_PART = re.compile(r"(\d+(?:\.\d+)?)(ms|us|ns|d|h|m|s)", re.I)
_NANOSECONDS = {"d": 86400000000000, "h": 3600000000000, "m": 60000000000,
                "s": 1000000000, "ms": 1000000, "us": 1000, "ns": 1}


def duration_literal(text: str) -> tuple[str, int]:
    prefix, body = text.lower().replace("_", "").split("#")
    dtype = "LTIME" if prefix.startswith("l") else "TIME"
    sign = -1 if body.startswith("-") else 1
    body = body.lstrip("-")
    parts = _DURATION_PART.findall(body)
    if not parts or "".join(n + unit for n, unit in parts) != body:
        raise ValueError(f"Invalid duration literal: {text}")
    scales = [_NANOSECONDS[unit] for _, unit in parts]
    if any(a <= b for a, b in zip(scales, scales[1:])) or (dtype == "TIME" and scales[-1] < 1000000):
        raise ValueError(f"Invalid duration units/order: {text}")
    total = sum(Decimal(n) * _NANOSECONDS[unit] for n, unit in parts)
    units = total if dtype == "LTIME" else total / 1000000
    limit = 2**64 if dtype == "LTIME" else 2**32
    if sign < 0 or units >= limit or units != int(units):
        raise ValueError(f"Duration outside supported unsigned {dtype} precision/range: {text}")
    return dtype, int(units)
_OPS = [
    ":=", "=>", "..",
    "**", "=", "<>", "<=", ">=", ":", ";", ",", "(", ")", "[", "]",
    "+", "-", "*", "/", "<", ">", "&", ".", "%", "^", "#",
]


def tokenize(src: str) -> tuple[list[Tok], list[Diag]]:
    """把源码切成 token。注释 (* *) 与 // 都被丢弃但保留行号。"""

    toks: list[Tok] = []
    diags: list[Diag] = []
    i, line, n = 0, 1, len(src)

    while i < n:
        c = src[i]

        # 空白与换行
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue

        # 注释 (* ... *) —— IEC 的标准注释，可嵌套
        if src.startswith("(*", i):
            depth, j = 1, i + 2
            while j < n and depth > 0:
                if src.startswith("(*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*)", j):
                    depth -= 1
                    j += 2
                else:
                    if src[j] == "\n":
                        line += 1
                    j += 1
            if depth > 0:
                diags.append(Diag("error", line, "E_UNCLOSED_COMMENT", "注释 (* 没有闭合"))
            i = j
            continue

        # 注释 // —— CODESYS 扩展
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue

        # 时间字面量 T#5s / TIME#1h30m
        if c == '{':
            pragma = re.match(r"\{\s*attribute\s+'(strict|qualified_only)'\s*\}", src[i:], re.I)
            if pragma:
                toks.append(Tok('pragma', pragma.group(1).lower(), line, i))
                line += pragma.group(0).count('\n')
                i += len(pragma.group(0))
                continue
        m = _TIME_RE.match(src, i)
        if m:
            try:
                dtype, value = duration_literal(m.group())
            except ValueError as exc:
                diags.append(Diag("error", line, "E_DURATION_LITERAL", str(exc)))
                dtype, value = "TIME", 0
            toks.append(Tok("num", m.group(), line, i, num=value, literal_type=dtype))
            for _ in range(m.group(0).count("\n")):
                line += 1
            i = m.end()
            continue

        # Typed numeric constants are one token; preserve the declared type for evaluation.
        typed=_TYPED_PREFIX_RE.match(src,i)
        if typed:
            dtype=typed[1].upper();start=typed.end();end=start;value=None
            if dtype=='BOOL':
                body=re.match(r'(TRUE|FALSE|0|1)(?![A-Za-z0-9_#])',src[start:],re.I)
                if body:
                    value=body[1].upper() in ('TRUE','1');end=start+body.end()
            else:
                sign=-1 if src[start:start+1]=='-' else 1
                number_start=start+int(src[start:start+1] in ('+','-'))
                body=_NUM_RE.match(src,number_start)
                if body:
                    text=body[0].replace('_','');end=body.end()
                    if body.group('base'):
                        base,digits=text.split('#',1);value=sign*int(digits,int(base))
                    elif body.group('real'):value=sign*float(text)
                    else:value=sign*int(text)
                    if dtype in ('REAL','LREAL'):value=float(value)
                    elif isinstance(value,float):
                        diags.append(Diag('error',line,'E_TYPED_LITERAL_TYPE','整数类型不能使用实数字面量'))
                    else:
                        bits=_INTEGER_BITS[dtype];unsigned=dtype.startswith('U') or dtype in ('BYTE','WORD','DWORD','LWORD')
                        lower=0 if unsigned else -(1<<(bits-1));upper=(1<<bits)-1 if unsigned or body.group('base') else (1<<(bits-1))-1
                        if not lower<=value<=upper:
                            diags.append(Diag('error',line,'E_TYPED_LITERAL_RANGE',f'字面量超出 {dtype} 范围'))
            if value is None:
                diags.append(Diag('error',line,'E_BAD_TYPED_LITERAL',f'{dtype} 字面量格式无效'))
                value=0
            toks.append(Tok('num',src[i:end],line,i,num=value,is_real=dtype in ('REAL','LREAL'),literal_type=dtype))
            i=end;continue

        # 数字字面量
        m = _NUM_RE.match(src, i)
        if m:
            text = m.group(0)
            if m.group("base"):
                base, digits = text.split("#", 1)
                val = int(digits.replace("_", ""), int(base))
                toks.append(Tok("num", text, line, i, num=val, is_real=False))
            elif m.group("real"):
                toks.append(Tok("num", text, line, i, num=float(text.replace("_", "")), is_real=True))
            else:
                toks.append(Tok("num", text, line, i, num=int(text.replace("_", "")), is_real=False))
            i = m.end()
            continue

        # 字符串 'abc' 或 "abc"
        if c in "'\"":
            quote = c
            j = i + 1
            buf = []
            while j < n and src[j] != quote:
                if src[j] == "\n":
                    line += 1
                buf.append(src[j])
                j += 1
            if j >= n:
                diags.append(Diag("error", line, "E_UNCLOSED_STRING", "字符串没有闭合"))
            toks.append(Tok("str", "".join(buf), line, i))
            i = j + 1
            continue

        # 标识符 / 关键字
        m = _ID_RE.match(src, i)
        if m:
            word = m.group(0)
            up = word.upper()
            kind = "kw" if up in KEYWORDS else "id"
            toks.append(Tok(kind, up if kind == "kw" else word, line, i))
            i = m.end()
            continue

        # 运算符（含 16# 之外的 # 字号后缀，直接当符号吃掉）
        for op in _OPS:
            if src.startswith(op, i):
                toks.append(Tok("op", op, line, i))
                i += len(op)
                break
        else:
            diags.append(Diag("error", line, "E_BAD_CHAR", f"无法识别的字符 {c!r}"))
            i += 1

    toks.append(Tok("eof", "<EOF>", line, i))
    return toks, diags


# --------------------------------------------------------------------------
# 语法树
# --------------------------------------------------------------------------


@dataclass
class Node:
    kind: str
    line: int
    # 表达式
    tok: Tok | None = None
    args: list["Node"] = field(default_factory=list)
    elifs: list[tuple["Node", list["Node"]]] = field(default_factory=list)
    else_body: list["Node"] = field(default_factory=list)
    # 语句
    stmts: list["Node"] = field(default_factory=list)
    # 推断类型（typecheck 填）
    typ: str | None = None
    call_names: list[str] = field(default_factory=list)

    def __repr__(self) -> str:
        return f"<{self.kind}@{self.line}>"


@dataclass
class Decl:
    """一个变量声明。"""

    name: str
    data_type: str  # 原样保存，如 "ARRAY[1..5] OF ST_Pump"
    section: str  # VAR_INPUT / VAR_OUTPUT / VAR_IN_OUT / VAR / VAR_TEMP / VAR_INST
    line: int
    init: Node | None = None


@dataclass
class POU:
    kind: str  # FUNCTION_BLOCK | FUNCTION | PROGRAM
    name: str
    line: int
    decls: list[Decl] = field(default_factory=list)
    body: list[Node] = field(default_factory=list)


@dataclass
class StructType:
    name: str
    fields: dict[str, str]


@dataclass
class EnumType:
    name: str
    members: dict[str, int]
    default: int
    base_type: str = 'INT'
    fields: dict[str, str] = field(default_factory=dict)
    strict: bool = False
    qualified_only: bool = False


# --------------------------------------------------------------------------
# 语法分析（递归下降）
# --------------------------------------------------------------------------


class ParseError(Exception):
    def __init__(self, diag: Diag):
        super().__init__(str(diag))
        self.diag = diag


class Parser:
    def __init__(self, toks: list[Tok]):
        self.toks = toks
        self.i = 0
        self.structs: dict[str, StructType] = {}
        self.pending_attrs: set[str] = set()

    # ---- token 工具 ----
    @property
    def cur(self) -> Tok:
        return self.toks[self.i]

    def peek(self, k: int = 1) -> Tok:
        j = min(self.i + k, len(self.toks) - 1)
        return self.toks[j]

    def advance(self) -> Tok:
        t = self.toks[self.i]
        self.i += 1
        return t

    def at(self, value: str) -> bool:
        t = self.cur
        return t.value == value or t.value.upper() == value.upper()

    def accept(self, value: str) -> bool:
        if self.at(value):
            self.advance()
            return True
        return False

    def expect(self, value: str) -> Tok:
        if not self.at(value):
            raise ParseError(
                Diag("error", self.cur.line, "E_EXPECT",
                     f"期望 {value!r}，实际是 {self.cur.value!r}")
            )
        return self.advance()

    # ---- 顶层 ----
    def parse_program(self) -> tuple[POU | None, list[Diag]]:
        diags: list[Diag] = []
        pou: POU | None = None
        try:
            while self.cur.kind != "eof":
                if self.cur.kind == 'pragma':
                    self.pending_attrs.add(self.advance().value)
                elif self.at("TYPE"):
                    self.parse_type_block()
                elif self.at("FUNCTION_BLOCK") or self.at("FUNCTION") or self.at("PROGRAM"):
                    if pou is not None:
                        # 允许多个 POU（题目常要求先定义类型再写 FB），只取第一个
                        self.skip_pou()
                        continue
                    pou = self.parse_pou()
                else:
                    diags.append(
                        Diag("warning", self.cur.line, "W_TRAILING",
                             f"POU 之外出现多余内容 {self.cur.value!r}，已忽略")
                    )
                    self.advance()
        except ParseError as e:
            diags.append(e.diag)
        return pou, diags

    def skip_pou(self) -> None:
        """跳过额外的 POU 定义（不参与类型检查）。"""
        depth = 0
        while self.cur.kind != "eof":
            v = self.cur.value
            if v in ("FUNCTION_BLOCK", "FUNCTION", "PROGRAM"):
                depth += 1
            elif v in ("END_FUNCTION_BLOCK", "END_FUNCTION", "END_PROGRAM"):
                depth -= 1
                self.advance()
                if depth <= 0:
                    return
                continue
            self.advance()

    def parse_type_block(self) -> None:
        """TYPE ... END_TYPE，只抽取 STRUCT 定义用于类型检查。"""
        self.expect("TYPE")
        while self.cur.kind != "eof" and not self.at("END_TYPE"):
            if self.cur.kind == 'pragma':
                self.pending_attrs.add(self.advance().value)
                continue
            if self.cur.kind == "id" and self.peek().value == ":":
                name = self.advance().value
                self.advance()  # :
                if self.at("STRUCT"):
                    self.advance()
                    fields: dict[str, str] = {}
                    while not self.at("END_STRUCT") and self.cur.kind != "eof":
                        fname = self.advance().value
                        self.expect(":")
                        ftype = self.parse_type_ref()
                        self.expect(";")
                        fields[fname] = ftype
                    self.accept("END_STRUCT")
                    self.structs[name] = StructType(name, fields)
                elif self.at('('):
                    self.advance()
                    members = {}
                    value = 0
                    while not self.at(')'):
                        token = self.advance()
                        if token.kind != 'id' or token.value.lower() in {m.lower() for m in members}:
                            raise ParseError(Diag('error', token.line, 'E_ENUM_MEMBER', '枚举成员必须唯一且有效'))
                        if self.accept(':='):
                            sign = -1 if self.accept('-') else 1
                            self.accept('+')
                            number = self.advance()
                            if number.kind != 'num' or number.is_real:
                                raise ParseError(Diag('error', number.line, 'E_ENUM_VALUE', '枚举值仅支持整数字面量'))
                            value = sign * int(number.num)
                        members[token.value] = value
                        value += 1
                        if not self.accept(','):
                            break
                    self.expect(')')
                    if len(members) < 2:
                        raise ParseError(Diag('error', self.cur.line, 'E_ENUM_MEMBER', '枚举至少需要两个成员'))
                    base = 'INT'
                    if self.cur.value.upper() in ELEMENTARY and ELEMENTARY[self.cur.value.upper()] == 'int':
                        base = self.advance().value.upper()
                    widths = {'SINT': (8, True), 'INT': (16, True), 'DINT': (32, True), 'LINT': (64, True),
                              'USINT': (8, False), 'UINT': (16, False), 'UDINT': (32, False), 'ULINT': (64, False),
                              'BYTE': (8, False), 'WORD': (16, False), 'DWORD': (32, False), 'LWORD': (64, False)}
                    bits, signed = widths[base]
                    lo, hi = (-(2 ** (bits - 1)), 2 ** (bits - 1) - 1) if signed else (0, 2 ** bits - 1)
                    if any(not lo <= n <= hi for n in members.values()):
                        raise ParseError(Diag('error', self.cur.line, 'E_ENUM_RANGE', '枚举值超出基础整数类型范围'))
                    default = 0 if 0 in members.values() else next(iter(members.values()))
                    if self.accept(':='):
                        initial = self.advance().value
                        if self.accept('.'):
                            if initial.lower() != name.lower():
                                raise ParseError(Diag('error', self.cur.line, 'E_ENUM_INIT', '枚举初值来自其它类型'))
                            initial = self.advance().value
                        found = [n for m, n in members.items() if m.lower() == initial.lower()]
                        if not found:
                            raise ParseError(Diag('error', self.cur.line, 'E_ENUM_INIT', '枚举初值不是已声明成员'))
                        default = found[0]
                    self.expect(';')
                    if any(key.lower() == name.lower() for key in self.structs):
                        raise ParseError(Diag('error', self.cur.line, 'E_DUP_TYPE', '重复类型声明'))
                    self.structs[name] = EnumType(name, members, default, base,
                        strict='strict' in self.pending_attrs, qualified_only='qualified_only' in self.pending_attrs)
                    self.pending_attrs.clear()
                else:
                    self.advance()
            else:
                self.advance()
        self.accept("END_TYPE")

    def parse_type_ref(self) -> str:
        """读一个类型引用，返回原文字符串（支持 ARRAY、结构体、元素类型）。

        **必须保留数组边界原文**：``ARRAY[1..5]`` 的上下界会被类型检查
        （常量下标越界）和仿真器（真实内存布局）同时依赖，丢掉就变成
        ``ARRAY[...]``，两处检查都会失效。同理 ``ARRAY[*]`` 保留星号。
        """
        if self.at("ARRAY"):
            self.advance()
            dims: list[str] = []
            while self.at("["):
                self.advance()
                buf: list[str] = []
                while self.cur.kind != "eof" and not self.at("]"):
                    tok = self.advance()
                    buf.append(tok.value)
                self.expect("]")
                dims.append("".join(buf))
            self.expect("OF")
            inner = self.advance().value
            return f"ARRAY[{', '.join(dims)}] OF {inner}"
        return self.advance().value

    def parse_pou(self) -> POU:
        kind_tok = self.advance()
        kind = kind_tok.value
        name_tok = self.advance()
        pou = POU(kind=kind, name=name_tok.value, line=kind_tok.line)

        # 返回类型（FUNCTION 可能带但题目不用）
        if self.at(":"):
            self.advance()
            self.parse_type_ref()

        # 声明段
        while self.cur.kind != "eof" and self.cur.value in (
            "VAR", "VAR_INPUT", "VAR_OUTPUT", "VAR_IN_OUT", "VAR_TEMP",
            "VAR_INST", "VAR_GLOBAL",
        ):
            pou.decls.extend(self.parse_var_block())

        # 实现体：IF ... END_IF 或声明结束符 END_VAR
        stopp = {"END_FUNCTION_BLOCK", "END_FUNCTION", "END_PROGRAM"}
        while self.cur.kind != "eof" and self.cur.value not in stopp:
            pou.body.append(self.parse_statement())
        if self.cur.kind == "eof":
            raise ParseError(
                Diag("error", self.cur.line, "E_MISSING_END_POU",
                     f"{kind} {pou.name} 缺少结束关键字")
            )
        self.advance()
        return pou

    def parse_var_block(self) -> list[Decl]:
        sec_tok = self.advance()
        section = sec_tok.value
        decls: list[Decl] = []
        # 跳过 CONSTANT / RETAIN 之类修饰
        while self.cur.value in ("CONSTANT", "RETAIN", "PERSISTENT"):
            self.advance()
        names: list[str] = []
        pending_names: list[tuple[str, int]] = []
        while self.cur.kind != "eof" and not self.at("END_VAR"):
            if self.at(";"):
                self.advance()
                pending_names = []
                continue
            if self.at(":"):
                self.advance()
                # 规范写法是 `名字 : 类型 := 初值;`：类型在前、初值在后。
                # 曾经这里把顺序写反了（先找 := 再找类型），于是 `rd : INT := 1;`
                # 被解析成"类型 INT"，后面那个 `:= 1` 被当成新声明开头吞掉，
                # 初值静默丢失——运行时 rd/wr 从 0 开始，数组下标直接越界。
                # 这是最隐蔽的一类 bug：不报错、不告警，逻辑却整片错位。
                dtype = self.parse_type_ref()
                init = None
                if self.accept(":="):
                    init = self.parse_expression()
                    # 也支持 `:= 初值` 后面再跟一点修饰（RETAIN 等）
                for nm, ln in pending_names:
                    decls.append(Decl(nm, dtype, section, ln, init))
                pending_names = []
                continue
            if self.cur.kind in ("id",):
                pending_names.append((self.cur.value, self.cur.line))
                names.append(self.cur.value)
                self.advance()
                continue
            if self.at(","):
                self.advance()
                continue
            # 出现的其它修饰符（AT %IW0 等）直接跳过
            self.advance()
        self.accept("END_VAR")
        return decls

    # ---- 语句 ----
    def parse_statement(self) -> Node:
        t = self.cur

        if self.at("IF"):
            return self.parse_if()

        if self.at("CASE"):
            return self.parse_case()

        if self.at("FOR"):
            return self.parse_for()

        if self.at("WHILE"):
            self.advance()
            cond = self.parse_expression()
            self.expect("DO")
            body = self.parse_block({"END_WHILE"})
            self.expect("END_WHILE")
            return Node("while", t.line, args=[cond], stmts=body)

        if self.at("REPEAT"):
            self.advance()
            body = self.parse_block({"UNTIL"})
            self.expect("UNTIL")
            cond = self.parse_expression()
            self.accept("END_REPEAT")
            return Node("repeat", t.line, args=[cond], stmts=body)

        if self.at("RETURN"):
            self.advance()
            self.accept(";")
            return Node("return", t.line)

        if self.at("EXIT"):
            self.advance()
            self.accept(";")
            return Node("exit", t.line)

        if self.at(";"):
            self.advance()
            return Node("nop", t.line)

        return self.parse_simple_statement()

    def parse_block(self, stop_words: set[str], case_branch: bool = False) -> list[Node]:
        """解析语句块直到遇到 stop_words 之一。

        ``case_branch=True`` 时额外把"下一个 CASE 标签行"当作停止条件：
        CASE 的分支体后面紧跟的可能是 ``3..5:`` 这样以字面量开头的行，
        它不是语句，硬解析会报 E_BAD_STMT，所以要先探测出标签边界。
        """
        out: list[Node] = []
        while self.cur.kind != "eof" and self.cur.value not in stop_words:
            if case_branch and self._at_case_label_start():
                break
            if self.cur.value in ("END_IF", "END_FOR", "END_CASE", "END_WHILE",
                                  "END_REPEAT", "END_FUNCTION_BLOCK", "END_FUNCTION",
                                  "END_PROGRAM", "ELSIF", "ELSE", "UNTIL"):
                raise ParseError(
                    Diag("error", self.cur.line, "E_UNEXPECTED",
                         f"意外的 {self.cur.value!r}（块没有正确闭合？）")
                )
            out.append(self.parse_statement())
        return out

    def _at_case_label_start(self) -> bool:
        """从当前位置向后找行尾，若这一行里有一个顶层 ':' 且其前是标签语法，
        就认为这是 CASE 的标签行。

        做法：扫描到 ';' 或下一个 CASE/END_CASE 关键字，看是否先遇到 ':'。
        标签行形如 ``1, 2:`` / ``3..5:`` / ``ELSE``，都不会以标识符+赋值号开头。
        """
        if self.at("ELSE") or self.at("END_CASE"):
            return True
        j = self.i
        depth = 0
        while j < len(self.toks):
            tv = self.toks[j].value
            if tv == "(":
                depth += 1
            elif tv == ")":
                depth -= 1
            elif depth == 0:
                if tv == ";":
                    return False
                if tv == ":":
                    return True
                if tv in ("END_CASE", "END_IF", "END_FOR", "END_FUNCTION_BLOCK",
                          "END_FUNCTION", "END_PROGRAM", "ELSE", "ELSIF"):
                    return True
                if tv == ":=":
                    return False
            j += 1
        return False

    def parse_if(self) -> Node:
        t = self.advance()  # IF
        node = Node("if", t.line)
        node.args = [self.parse_expression()]
        self.expect("THEN")
        node.stmts = self.parse_block({"ELSIF", "ELSE", "END_IF"})
        while self.at("ELSIF"):
            self.advance()
            cond = self.parse_expression()
            self.expect("THEN")
            body = self.parse_block({"ELSIF", "ELSE", "END_IF"})
            node.elifs.append((cond, body))
        if self.at("ELSE"):
            self.advance()
            node.else_body = self.parse_block({"END_IF"})
        self.expect("END_IF")
        self.accept(";")
        return node

    def parse_case(self) -> Node:
        t = self.advance()
        selector = self.parse_expression()
        self.expect("OF")
        node = Node("case", t.line, args=[selector])
        while self.cur.kind != "eof" and not self.at("END_CASE"):
            if self.at("ELSE"):
                self.advance()
                node.else_body = self.parse_block({"END_CASE"})
                continue
            # 标签：1, 2..5, 7 :   （".." 是范围，需要单独成一个节点）
            labels: list[Node] = []
            while not self.at(":"):
                if self.cur.kind == "eof":
                    raise ParseError(Diag("error", t.line, "E_CASE_LABEL", "CASE 标签缺少 ':'"))
                if self.at(","):
                    self.advance()
                    continue
                first = self.parse_expression()
                # 范围标签 3..5：parse_expression 吃到 3 就停了（".." 不是
                # 比较/算术运算符），所以这里再判一次。
                if self.at(".."):
                    self.advance()
                    second = self.parse_expression()
                    labels.append(Node("range", first.line, args=[first, second]))
                else:
                    labels.append(first)
            self.expect(":")
            body = self.parse_block({"END_CASE", "ELSE"}, case_branch=True)
            node.elifs.append((Node("case_label", t.line, args=labels), body))
        self.expect("END_CASE")
        self.accept(";")
        return node

    def parse_for(self) -> Node:
        t = self.advance()
        var = self.parse_postfix()
        self.expect(":=")
        start = self.parse_expression()
        self.expect("TO")
        end = self.parse_expression()
        step = None
        if self.at("BY"):
            self.advance()
            step = self.parse_expression()
        self.expect("DO")
        body = self.parse_block({"END_FOR"})
        self.expect("END_FOR")
        self.accept(";")
        args = [start, end] + ([step] if step else [])
        return Node("for", t.line, tok=var.tok, args=args, stmts=body)

    def parse_simple_statement(self) -> Node:
        t = self.cur
        target = self.parse_postfix()

        # 无参函数调用语句：Foo;  (少见但语法上合法)
        if self.accept(";"):
            if target.kind == "call":
                return target
            return Node("exprstmt", t.line, args=[target])

        if self.at(":="):
            self.advance()
            value = self.parse_expression()
            self.accept(";")
            return Node("assign", t.line, tok=target.tok, args=[target, value])

        # 带参数的调用语句：Foo(a := 1);
        if self.at("("):
            call = self.parse_call_args(target)
            self.accept(";")
            return call

        # 裸表达式语句（例如漏了 := 左边的赋值）：
        # 这里给一个明确的诊断，而不是把下一个 token 报成"无法解析"，
        # 因为真实编译器会直接指出"缺少赋值号"。
        if self.at(":"):
            raise ParseError(
                Diag("error", t.line, "E_MISSING_ASSIGN",
                     "缺少赋值运算符 ':='（或把 ':' 用在了不该出现的位置）")
            )

        raise ParseError(
            Diag("error", t.line, "E_BAD_STMT",
                 f"无法解析的语句，遇到 {self.cur.value!r}")
        )

    # ---- 表达式 ----
    def parse_expression(self) -> Node:
        return self.parse_or()

    def parse_or(self) -> Node:
        left = self.parse_and()
        while self.at("OR") or self.at("XOR"):
            op = self.advance()
            right = self.parse_and()
            left = Node("binop", op.line, tok=Tok("op", op.value, op.line), args=[left, right])
        return left

    def parse_and(self) -> Node:
        left = self.parse_compare()
        while self.at("AND"):
            op = self.advance()
            right = self.parse_compare()
            left = Node("binop", op.line, tok=Tok("op", "AND", op.line), args=[left, right])
        return left

    def parse_compare(self) -> Node:
        left = self.parse_add()
        while self.cur.value in ("=", "<>", "<", ">", "<=", ">="):
            op = self.advance()
            right = self.parse_add()
            left = Node("binop", op.line, tok=Tok("op", op.value, op.line), args=[left, right])
        return left

    def parse_add(self) -> Node:
        left = self.parse_mul()
        while self.cur.value in ("+", "-", "&"):
            op = self.advance()
            right = self.parse_mul()
            left = Node("binop", op.line, tok=Tok("op", op.value, op.line), args=[left, right])
        return left

    def parse_mul(self) -> Node:
        left = self.parse_shift()
        while self.cur.value in ("*", "/", "MOD") or (self.cur.kind == "kw" and self.cur.value == "MOD"):
            op = self.advance()
            right = self.parse_shift()
            left = Node("binop", op.line, tok=Tok("op", op.value, op.line), args=[left, right])
        return left

    def parse_shift(self) -> Node:
        """中缀移位/循环移位：``a SHL n`` / ``a ROL n``。

        IEC 61131-3 里 SHL/SHR/ROL/ROR 是**中缀运算符**。此前只在
        STD_FUNCS 里登记了函数形式 ``SHL(a, n)``，解析器没有对应分支，
        于是 ``x SHR i`` 直接报"期望 ')'"——位操作类题目（如 DWORD
        边沿检测）因此根本写不出来。函数形式保留，两者等价。
        """
        left = self.parse_unary()
        while self.cur.kind == "kw" and self.cur.value in ("SHL", "SHR", "ROL", "ROR"):
            op = self.advance()
            right = self.parse_unary()
            left = Node("binop", op.line, tok=Tok("op", op.value, op.line), args=[left, right])
        return left

    def parse_unary(self) -> Node:
        if self.at("NOT") or self.at("-") or self.at("+"):
            op = self.advance()
            operand = self.parse_unary()
            return Node("unop", op.line, tok=Tok("op", op.value, op.line), args=[operand])
        return self.parse_postfix()

    def parse_postfix(self) -> Node:
        node = self.parse_primary()
        while True:
            if self.at("["):
                lb = self.advance()
                idxs = [self.parse_expression()]
                while self.accept(","):
                    idxs.append(self.parse_expression())
                self.expect("]")
                node = Node("index", lb.line, args=[node, *idxs])
                continue
            if self.at("."):
                self.advance()
                fld = self.advance()
                node = Node(
                    "member", fld.line,
                    tok=Tok("id", fld.value, fld.line),
                    args=[node],
                )
                continue
            if self.at("("):
                node = self.parse_call_args(node)
                continue
            break
        return node

    def parse_call_args(self, callee: Node) -> Node:
        self.expect("(")
        args: list[Node] = []
        names = []
        if not self.at(")"):
            while True:
                name = ""
                if self.cur.kind == "id" and self.peek().value in (":=", "=>"):
                    name = self.advance().value.upper() + self.advance().value
                names.append(name)
                args.append(self.parse_expression())
                if not self.accept(","):
                    break
        self.expect(")")
        return Node("call", callee.line, tok=callee.tok, args=args, call_names=names)

    def parse_primary(self) -> Node:
        t = self.cur

        if t.kind == "num":
            self.advance()
            n = Node("num", t.line, tok=t)
            n.typ = t.literal_type or ("REAL" if t.is_real else "INT")
            return n

        if t.kind == "str":
            self.advance()
            n = Node("str", t.line, tok=t)
            n.typ = "STRING"
            return n

        if t.value in ("TRUE", "FALSE"):
            self.advance()
            n = Node("bool", t.line, tok=t)
            n.typ = "BOOL"
            return n

        if self.at("("):
            self.advance()
            inner = self.parse_expression()
            self.expect(")")
            return inner

        if t.kind in ("id", "kw"):
            self.advance()
            return Node("name", t.line, tok=t)

        raise ParseError(
            Diag("error", t.line, "E_BAD_EXPR", f"表达式中意外的 {t.value!r}")
        )


# --------------------------------------------------------------------------
# 对外入口
# --------------------------------------------------------------------------


@dataclass
class CompileResult:
    ok: bool
    diags: list[Diag] = field(default_factory=list)
    pou: POU | None = None
    structs: dict[str, StructType] = field(default_factory=dict)

    @property
    def errors(self) -> list[Diag]:
        return [d for d in self.diags if d.level == "error"]

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "problems": [d.to_dict() for d in self.diags],
        }


def compile_st(src: str) -> CompileResult:
    """编译入口：词法 → 语法 → 待 typecheck（由 typecheck.py 补上）。"""

    toks, lex_diags = tokenize(src)
    parser = Parser(toks)
    pou, parse_diags = parser.parse_program()
    diags = lex_diags + parse_diags
    if any(d.level == "error" for d in diags):
        return CompileResult(ok=False, diags=diags, pou=pou, structs=parser.structs)
    return CompileResult(ok=True, diags=diags, pou=pou, structs=parser.structs)
