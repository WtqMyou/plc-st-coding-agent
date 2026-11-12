"""Native BYTE conversion context for STRING indexing; original course character view remains."""
from stbench.st import interp


def install():
    original=interp.Interpreter._call

    def call(self,node):
        name=(node.tok.value if node.tok else '').upper()
        if name.startswith('BYTE_TO_') and len(node.args)==1:
            operand=node.args[0]
            if operand.kind=='index' and len(operand.args)==2 and operand.args[1].kind!='range':
                base_type=(operand.args[0].typ or '').upper()
                if base_type.startswith('STRING'):
                    value=self.eval(operand.args[0]);index=int(self.eval(operand.args[1]))
                    if not isinstance(value,str) or not 0<=index<=len(value):
                        raise interp.SimError('Unsupported modeling: STRING byte access beyond terminator',node.line)
                    if any(ord(char)>127 for char in value):
                        raise interp.SimError('Unsupported modeling: non-ASCII STRING code page',node.line)
                    byte=ord(value[index]) if index<len(value) else 0
                    dst=name.split('_TO_',1)[1]
                    if dst in interp._INT_TYPES:return interp._wrap_int(byte,dst)
                    if dst in interp._REAL_TYPES:return float(byte)
                    if dst in interp._BOOL_TYPES:return bool(byte)
        try:return original(self,node)
        except (ValueError,TypeError,OverflowError) as exc:
            if '_TO_' not in name and not name.startswith('TO_'):raise
            raise interp.SimError('Unsupported modeling: conversion '+name+' ('+type(exc).__name__+')',node.line) from None

    interp.Interpreter._call=call

