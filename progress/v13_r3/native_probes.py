"""Native observations used to decide the scope of the string arithmetic guard."""
import r3_revision as v
from stbench.schema import Problem


def examples(kind='core'):
    def make(pid, dtype, body, expected=None):
        p=Problem.from_dict(dict(pid=pid,source='selfmade',difficulty='easy',title=pid,requirements='Native type observation',
            variables=[dict(name='text',data_type='STRING(20)',direction='input'),dict(name='value',data_type=dtype,direction='output')]))
        code=f'FUNCTION_BLOCK FB\nVAR_INPUT text:STRING(20); END_VAR\nVAR_OUTPUT value:{dtype}; END_VAR\n{body}\nEND_FUNCTION_BLOCK'
        return dict(problem=p,code=code,expected=expected)
    if kind=='indexing':
        return [make('index-minus-literal','INT',"value := text[1] - '0';"),
                make('index-minus-byte','INT',"value := text[1] - BYTE#48;")]
    rows=[
        make('string-sub','INT',"value := MID(text,1,1) - '0';",'failed'),
        make('string-add','STRING(20)',"value := MID(text,1,1) + 'x';"),
        make('string-mul','INT',"value := MID(text,1,1) * 2;",'failed'),
        make('string-negative','INT',"value := -MID(text,1,1);",'failed'),
        make('string-convert','INT',"value := STRING_TO_INT(MID(text,1,1)) + 1;",'passed'),
        make('string-compare','BOOL',"value := MID(text,1,1) >= '0';",'passed'),
        make('string-concat','STRING(20)',"value := CONCAT(MID(text,1,1),'x');",'passed'),
    ]
    p=next(p for p in v.problems() if p.pid=='public-medium-08');q,_,_=v.adapt(p)
    rows.append(dict(problem=q,code=v.historical_candidate(),expected={'codesys':'failed','openplc':'passed'}))
    return rows
