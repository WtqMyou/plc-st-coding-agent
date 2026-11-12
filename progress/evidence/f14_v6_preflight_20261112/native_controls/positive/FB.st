TYPE ST_V6_Copy : STRUCT ident:INT; items:ARRAY[0..1] OF INT; END_STRUCT END_TYPE
FUNCTION_BLOCK FB
VAR_OUTPUT copyPassed:BOOL;arrayPassed:BOOL;realPassed:BOOL;stringPassed:BOOL;END_VAR
VAR originalRecord,copiedRecord:ST_V6_Copy;originalArray,copiedArray:ARRAY[0..1] OF INT;
txt:STRING(8):='1.'; narrowReal:REAL;wideReal:LREAL;END_VAR
originalRecord.ident:=7;originalRecord.items[0]:=11;copiedRecord:=originalRecord;
copiedRecord.ident:=0;copiedRecord.items[0]:=0;
copyPassed:=(originalRecord.ident=7) AND (originalRecord.items[0]=11);
originalArray[0]:=3;copiedArray:=originalArray;copiedArray[0]:=0;
arrayPassed:=(originalArray[0]=3);
narrowReal:=TO_REAL(DINT#16777217);wideReal:=TO_LREAL(DINT#16777217);
realPassed:=(narrowReal=REAL#16777216.0) AND (wideReal=LREAL#16777217.0);
stringPassed:=(BYTE_TO_INT(txt[0])=49) AND (BYTE_TO_INT(txt[1])=46) AND (BYTE_TO_INT(txt[2])=0);
END_FUNCTION_BLOCK