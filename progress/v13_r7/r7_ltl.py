"""Two parser corrections over the frozen LTL implementation; semantics stay pinned."""
import r7_revision
from stbench import ltl as parent
from stbench.st.frontend import Parser as ExpressionParser,tokenize

LtlNode,Verdict=parent.LtlNode,parent.Verdict
LTLParseError=parent.LTLParseError


class Parser(parent._Parser):
    def p_unary(self):
        # The lexer classifies the word NOT as an identifier. It must still
        # negate an LTL subtree, including history and edge operators.
        if self.cur.text.upper() in ('NOT','!','~','¬'):
            self.i+=1
            return LtlNode('not',(self.p_unary(),))
        return super().p_unary()

    def p_atom(self):
        # A numeric literal can begin a comparison: 0 < prev(count). Consuming
        # only its first token leaves the rest of a valid expression unparsed.
        if self.cur.kind=='num':return self._collect_atom()
        return super().p_atom()


def parse(source):
    if not source or not source.strip():raise LTLParseError('LTL formula is empty')
    text=source.strip()
    for old,new in parent._UNICODE_OPS:text=text.replace(old,new)
    return Parser(text).parse()


def evaluate(formula,*args,**kwargs):
    return parent.evaluate(parse(formula) if isinstance(formula,str) else formula,*args,**kwargs)


def explain(formula,*args,**kwargs):
    return parent.explain(parse(formula) if isinstance(formula,str) else formula,*args,**kwargs)


def formula_names(formula):
    names=set()
    def expression(node):
        if node.kind=='name':names.add(node.tok.value.lower())
        for child in node.args:expression(child)
    def visit(node):
        if node.kind=='atom':
            tokens,errors=tokenize(node.text)
            if errors:raise ValueError('Invalid formula atom')
            expression(ExpressionParser(tokens).parse_expression())
        for child in node.args:visit(child)
    visit(parse(formula))
    return names
