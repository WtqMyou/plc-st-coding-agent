FUNCTION_BLOCK FB
VAR_INPUT signal:BOOL; END_VAR
VAR_OUTPUT rQ:BOOL; fQ:BOOL; bits:DWORD; bitHigh:BOOL; END_VAR
VAR riseDetector:R_TRIG; fallDetector:F_TRIG; x:DWORD; END_VAR
riseDetector(CLK:=signal,Q=>rQ); fallDetector(CLK:=signal,Q=>fQ);
x:=DWORD#16#80000001; bitHigh:=x.31 AND x.0;
x.0:=FALSE; x.30:=TRUE; bits:=x;
END_FUNCTION_BLOCK