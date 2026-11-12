"""R9 formula overlays; original datasets and expected outputs remain intact."""
from .ltl import parse
from .st.frontend import Parser, tokenize


def formula_names(formula):
    result = set()
    def expression(node):
        if node.kind == 'name':
            result.add(node.tok.value.lower())
        for child in node.args:
            expression(child)
    def visit(node):
        if node.kind == 'atom':
            tokens, errors = tokenize(node.text)
            if errors:
                raise ValueError('Invalid formula atom')
            expression(Parser(tokens).parse_expression())
        for child in node.args:
            visit(child)
    visit(parse(formula))
    return result


def apply(problem):
    if problem.provenance.get("release_contract") == "STBench-F1.4":
        return
    if problem.pid in {'self-hard-05','self-hard-06','self-hard-07','self-medium-05','self-medium-06'}:
        problem.provenance['upstream_review_claim'] = problem.provenance.get('review','')
        problem.provenance['review'] = '自动工程复核；人工工艺审核待确认，不将上游审核字样视为签署证据'
        problem.provenance['human_process_review'] = dict(status='pending',reviewer=None,date=None)
    observer = None
    changes = []
    if problem.pid == 'public-medium-08':
        observer = 'ipv4'
        problem.requirements += ('\nR9 明确原有用例采用的文本约定：每段允许单个 0，'
                                 '其他段须以 1..9 开头；多位前导零非法。原用例期望不变。')
        replacements = {
            'S1': ('非法 IPv4 输入必须输出 0，合法性由公开输入计算。', 'G(NOT __spec_ip_valid -> ipValue = 0)'),
            'S2': ('合法四段 IPv4 按网络字节序输出；不约束候选内部计数器。',
                   'G(__spec_ip_valid -> ipValue = __spec_ip_value)'),
            'S3': ('只有四段全 255 的合法输入才允许输出最大地址。',
                   'G(ipValue = 4294967295 -> __spec_ip_valid AND __spec_ip_value = 4294967295)'),
            'S4': ('对输入文本的合法/非法映射逐扫描比较；观察量来自公开输入。',
                   'G(ipValue = __spec_ip_value)'),
        }
    elif problem.pid == 'public-hard-02':
        observer = 'process'
        replacements = {
            'S2': ('输入契约内，观察器判定空闲时输送带静止。',
                   'G(__spec_contract AND __spec_idle -> NOT conveyorLeft AND NOT conveyorRight)'),
            'S3': ('输入契约内，等待加工完成时输送带静止。',
                   'G(__spec_contract AND __spec_wait -> NOT conveyorLeft AND NOT conveyorRight)'),
            'S4': ('输入契约内，下一目标在右侧且未到位时正转。',
                   'G(__spec_contract AND __spec_right -> conveyorRight AND NOT conveyorLeft)'),
            'S5': ('输入契约内，下一目标在左侧且未到位时反转。',
                   'G(__spec_contract AND __spec_left -> conveyorLeft AND NOT conveyorRight)'),
            'S6': ('当前工位完成信号上升沿推进一工序后，输送输出须符合下一目标。只检验可观察效果，不断言私有 idx。',
                   'G(__spec_contract AND __spec_complete -> conveyorLeft = __spec_left AND conveyorRight = __spec_right)'),
            'S7': ('输入契约内，有未到达的不同目标时必须输出一个输送方向。',
                   'G(__spec_contract AND (__spec_left OR __spec_right) -> conveyorLeft OR conveyorRight)'),
        }
    else:
        replacements = {}
    if problem.pid == 'self-easy-01':
        clauses = []
        for n in range(1, 9):
            total = '+'.join(f'INT_TO_DINT(values[{i}])' for i in range(1, n + 1))
            condition = f'count = {n}' if n < 8 else 'count >= 8'
            clauses.append(f'(enable AND avgEnable AND {condition} -> ABS(avgOut - DINT_TO_REAL({total}) / {n}.0) <= 0.000001)')
        replacements['S4'] = ('投入且样本数为正时输出有效前缀平均值；超过八个按八个计算，浮点比较容差 1e-6。',
                              'G(' + ' AND '.join(clauses) + ')')
    if problem.pid == 'self-medium-05':
        reset = '(resetBtn AND NOT prev(resetBtn))'
        active = f'(enable AND NOT dataFault AND NOT {reset})'
        formula = ('G(ABS(revenue - qualifiedTon * 280.0) <= 0.000001 AND '
                   'ABS(cost - fuelTon * 1500.0) <= 0.000001 AND '
                   'ABS(netProfit - (revenue - cost)) <= 0.000001 AND '
                   f'({active} AND qualified -> ABS(qualifiedTon - (prev(qualifiedTon) + steamFlow * scanSeconds / 1000.0)) <= 0.000001) AND '
                   f'({active} -> ABS(fuelTon - (prev(fuelTon) + fuelFlow * scanSeconds / 1000.0)) <= 0.000001))')
        # v1.3 将 v1.2 的 S8 重编号为 S10（文本不变，仍为纯仿真规约）
        replacements['S10'] = ('公开输入和累计输出的增量及收入成本关系；复位拍不累计，浮点容差 1e-6。', formula)
    if problem.pid == 'self-medium-06':
        inactive = '(NOT enable OR fault OR (resetBtn AND NOT prev(resetBtn)))'
        # v1.3 将 v1.2 的 S6 重编号为 S10（文本不变，仍为纯仿真规约）
        replacements['S10'] = ('有效工作拍功率为 bias 加修正后的 0..100 钳位；停用、故障或复位拍为零。',
            f'G(({inactive} -> power = 0.0) AND (NOT {inactive} -> ABS(power - LIMIT(0.0, bias + correction, 100.0)) <= 0.000001))')
    for spec in problem.specs:
        if spec.sid in replacements:
            changes.append(dict(sid=spec.sid, original_ltl=spec.ltl, original_text=spec.text,
                                original_verified_by=spec.verified_by))
            spec.text, spec.ltl = replacements[spec.sid]
        if spec.ltl:
            spec.verified_by = 'bounded_checker'
    problem.provenance['r9_spec_policy'] = dict(observer=observer, changes=changes,
        note='Observer names are verification-only; candidate must implement only its public interface')
