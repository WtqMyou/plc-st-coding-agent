"""Explicit, versioned platform adaptations. Never relabel these as original tasks."""
from __future__ import annotations
import copy
import hashlib
import re
from .schema import VarDef, Direction

PROFILE="portable-frame-v4"

def adapt(problem,src,platform):
    p=copy.deepcopy(problem)
    rules=[]
    if p.pid in ("self-medium-05", "self-medium-06", "self-hard-07"):
        # DT is the IEC DATE_AND_TIME alias, reserved by both native compilers.
        src=re.sub(r"\bdt\b", "scanSeconds", src, flags=re.I)
        for v in p.variables:
            if v.name.lower()=="dt":v.name="scanSeconds"
        for case in p.test_cases:
            for field in ("inputs", "const_inputs", "init"):
                values=getattr(case,field)
                if "dt" in values:values["scanSeconds"]=values.pop("dt")
        if "dt" in p.mc_inputs:p.mc_inputs["scanSeconds"]=p.mc_inputs.pop("dt")
        for spec in p.specs:
            spec.ltl=re.sub(r"\bdt\b", "scanSeconds", spec.ltl, flags=re.I)
            spec.text=re.sub(r"\bdt\b", "scanSeconds", spec.text, flags=re.I)
        p.requirements=re.sub(r"\bdt\b", "scanSeconds", p.requirements, flags=re.I)
        p.requirements+="\n平台适配：原接口 dt（IEC 日期时间类型别名）统一重命名为 scanSeconds；单位秒、类型及原数字断言不变。"
        rules.append("Reserved input dt -> scanSeconds in interface, tests and LTL; same seconds and numeric behavior")
    # Existing benchmark already defines these accumulators in scan-count units.
    if any(v.data_type.upper()=="LTIME" for v in p.variables):
        for v in p.variables:
            if v.data_type.upper()=="LTIME":v.data_type="LINT"
        src=re.sub(r"\bLTIME\b","LINT",src)
        rules.append("LTIME accumulators -> LINT scan counters; native time generality not claimed")
    converted=re.sub(r"\b(\w+)\s+(SHR|SHL)\s+(\d+)\b",lambda m:m[2]+"("+m[1]+", "+m[3]+")",src,flags=re.I)
    if converted!=src:
        rules.append("Infix bit shift -> IEC SHL/SHR function; same operands")
        src=converted
    if p.pid=="public-hard-02":
        src=re.sub(r"\blenNow\s*:=\s*processLength\s*;","lenNow := USINT_TO_INT(processLength);",src)
        src=re.sub(r"\bdstStation\s*:=\s*(processSequence\[[^\]]+\])\s*;",
                   r"dstStation := USINT_TO_INT(\1);",src)
        rules.append("Explicit widening of processSequence USINT elements to INT")
    if p.pid=="public-medium-08":
        src=re.sub(r"\bs\b","scanText",src)
        src=re.sub(r"\bch\s*:=\s*scanText\[i\]\s*;","ch := MID(scanText, 1, i);",src)
        src=src.replace("ipValue * 256 + segments[i]","ipValue * INT_TO_UDINT(256) + INT_TO_UDINT(segments[i])")
        p.requirements+="\n平台约定：内部字符串临时变量避免使用单字母 s；当前平台对原写法报告词法冲突，接口保持原样。"
        p.requirements+=" 字符提取使用 MID(text,1,index) 返回单字符字符串；地址拼装保持 UDINT 无符号运算。"
        rules.append("Internal string temporary s -> scanText after native CODESYS token diagnostics; no interface change")
        rules.append("String character extraction uses MID; IPv4 assembly uses explicit UDINT operands")
    if p.pid=="self-medium-01":
        src=re.sub(r"\br\b","selectedRecipe",src)
        p.requirements+="\n平台约定：内部结构体临时变量避免使用单字母 r；当前平台对原写法报告词法冲突，接口保持原样。"
        rules.append("Internal recipe temporary r -> selectedRecipe after native CODESYS token diagnostics")
    if p.pid=="self-hard-04":
        src=re.sub(r"\btmp\s*:\s*LINT\s*;","tmp : INT;",src)
        rules.append("Pump-index swap temporary LINT -> INT; temporary holds indices 1..5, not run hours")
    if p.pid=="public-hard-04":
        # A bounded DINT specialization of the generic VARIANT task, capacity explicit.
        # Keep all original 27 output assertions; padding affects storage only.
        capacities=[len(c.init["buffer"]) for c in p.test_cases if isinstance(c.init.get("buffer"),list)]
        maximum=max(capacities)
        for v in p.variables:
            if v.name=="item":v.data_type="DINT"
            if v.name=="buffer":v.data_type=f"ARRAY[1..{maximum}] OF DINT"
        p.variables.append(VarDef("capacity","DINT","Logical storage capacity; 1.."+str(maximum),Direction.INPUT))
        cap=maximum
        for c in p.test_cases:
            if isinstance(c.init.get("buffer"),list):
                cap=len(c.init["buffer"])
                c.init["buffer"]=c.init["buffer"]+[0]*(maximum-cap)
            c.const_inputs["capacity"]=cap
        src=re.sub(r"\bitem\s*:\s*VARIANT\b","item : DINT",src,flags=re.I)
        src=re.sub(r"\bbuffer\s*:\s*VARIANT\b",f"buffer : ARRAY[1..{maximum}] OF DINT",src,flags=re.I)
        src=re.sub(r"\bVAR_INPUT\b","VAR_INPUT\n capacity : DINT;",src,count=1,flags=re.I)
        src=src.replace("cap := UPPER_BOUND(buffer, 1);","cap := capacity;")
        src=src.replace("(* 容量每拍从调用方数组重新取：数组换长度时行为随之改变 *)",
                        "(* 固定调用方绑定：capacity 在本次运行中保持不变；不同绑定分别验证。 *)")
        for spec in p.specs:
            if spec.ltl:spec.ltl=re.sub(r'\bcap\b','capacity',spec.ltl,flags=re.I)
            spec.text=re.sub(r'\bcap\b','capacity',spec.text,flags=re.I)
        p.mc_inputs['capacity']=sorted(set(capacities))
        p.mc_fixed_inputs=['capacity']
        p.requirements+="\n平台适配：item 固定为 DINT，buffer 是固定容量 DINT 数组；capacity 输入给定本次绑定的有效容量。算法仍须支持两种容量，复位/上下沿和状态码规则保持。"
        p.requirements+=" 每次绑定后 capacity 在本次运行中保持不变；分别支持不同容量的运行，不要求运行中缩容或切换缓冲区。"
        rules.append("VARIANT -> bounded DINT FIFO, logical capacity input; not a proof for arbitrary element types")
        rules.append("FIFO LTL cap -> explicit capacity input; independent of reference-local variable names")
        rules.append("Capacity binding is fixed within each trace; enumerate both original capacities across traces, no dynamic-resize claim")
    p.provenance["platform_adaptation"]={"profile":PROFILE,"platform":platform,"rules":rules,
                                        "original_pid":problem.pid}
    return p,src,dict(profile=PROFILE,platform=platform,pid=p.pid,rules=rules,
                     adapted_source_sha256=hashlib.sha256(src.encode()).hexdigest())
