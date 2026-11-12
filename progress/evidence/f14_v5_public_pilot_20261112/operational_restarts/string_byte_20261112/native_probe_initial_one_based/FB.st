FUNCTION_BLOCK FB
VAR_OUTPUT firstByte:INT;dotByte:INT;endByte:INT;END_VAR
VAR txt:STRING(8):='1.';END_VAR
firstByte:=BYTE_TO_INT(txt[1]);dotByte:=BYTE_TO_INT(txt[2]);endByte:=BYTE_TO_INT(txt[3]);
END_FUNCTION_BLOCK