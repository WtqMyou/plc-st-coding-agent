FUNCTION_BLOCK DialectProbe
VAR_INPUT gate:BOOL; count:UINT; duration:LTIME; END_VAR
VAR_OUTPUT value:DINT;END_VAR
VAR message:STRING:='END_IF';END_VAR
value:=0;
IF gate THEN
 IF count>UINT#40000 THEN value:=1;END_IF;
ELSE
 (* true nested IF, not an ELSIF rewrite *)
 IF duration>LTIME#1ns THEN value:=2;END_IF;
END_IF;
END_FUNCTION_BLOCK