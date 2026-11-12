```st
FUNCTION_BLOCK FB_IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    i : INT;
    len : INT;
    ch : BYTE;
    digitsInSeg : INT;
    segCount : INT;
    curVal : UDINT;
    result : UDINT;
END_VAR

ipValue := 0;
digitsInSeg := 0;
segCount := 0;
curVal := 0;
result := 0;

len := LEN(ipText);

FOR i := 1 TO len DO
    ch := ipText[i];
    IF (ch >= BYTE#48) AND (ch <= BYTE#57) THEN
        curVal := (curVal * UDINT#10) +