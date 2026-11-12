FUNCTION_BLOCK FB_IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR

VAR_OUTPUT
    ipValue : UDINT := 0;
END_VAR

VAR
    tmp_pos : INT;
    tmp_len : INT;
    tmp_char : BYTE;
    tmp_digit : INT;
    tmp_segCount : INT;
    tmp_segValue : INT;
    tmp_invalid : BOOL;
    tmp_result : UDINT;
    tmp_segments : ARRAY[1..4] OF INT;
    tmp_inSegment : BOOL;
END_VAR

(* ENGINEERING_CONTRACT *)
(*
PUB001: Parse dotted-decimal IPv4 string to 32-bit UDINT in network byte order.
PUB002: Validate 4 segments, each 0-255, with nonempty decimal-only octets.
PUB003: Network byte order: seg1=MSB(31:24), seg2=(23:16), seg3=(15:8), seg4=LSB(7:0).
PUB004: Invalid input → ipValue=0; 0.0.0.0 also yields 0.

| Output/State    | Activation | Retention | Reset/Deactivation | Scan Priority | Units/Boundaries    |
|-----------------|------------|-----------|-------------------|---------------|---------------------|
| ipValue         | Every scan | None      | Overwritten next  | Same-scan     | UDINT [0,16#FFFFFFFF] |
| tmp_invalid     | Every scan | None      | Overwritten next  | Same-scan     | BOOL                |
| tmp_segCount    | Loop init  | None      | Overwritten next  | Same-scan     | INT [0,4]           |
| tmp_segValue    | Loop/period| None      | Overwritten next  | Same-scan     | INT [0,255]         |
| tmp_segments[1..4] | Parse end | None    | Overwritten next  | Same-scan     | INT [0,255] each    |
*)
tmp_invalid := FALSE;
tmp_pos := 0;
tmp_len := LEN(ipText);
tmp_segCount := 0;
tmp_segValue := 0;
tmp_result := 0;
tmp_inSegment := FALSE;

tmp_segments[1] := 0;
tmp_segments[2] := 0;
tmp_segments[3] := 0;
tmp_segments[4] := 0;

IF tmp_len = 0 THEN
    tmp_invalid := TRUE;
ELSE
    WHILE tmp_pos < tmp_len AND NOT tmp_invalid DO
        tmp_char := ipText[tmp_pos];
        IF tmp_char >= 16#30 AND tmp_char <= 16#39 THEN
            tmp_digit := TO_INT(tmp_char) - 16#30;
            IF tmp_segValue > 25 THEN
                tmp_invalid := TRUE;
            ELSIF tmp_segValue = 25 AND tmp_digit > 5 THEN
                tmp_invalid := TRUE;
            ELSE
                tmp_segValue := tmp_segValue * 10 + tmp_digit;
            END_IF;
        ELSIF tmp_char = 16#2E THEN
            IF tmp_segCount >= 4 THEN
                tmp_invalid := TRUE;
            ELSE
                tmp_segCount := tmp_segCount + 1;
                tmp_segments[tmp_segCount] := tmp_segValue;
                tmp_segValue := 0;
            END_IF;
        ELSE
            tmp_invalid := TRUE;
        END_IF;
        tmp_pos := tmp_pos + 1;
    END_WHILE;
    
    IF NOT tmp_invalid THEN
        tmp_segCount := tmp_segCount + 1;
        tmp_segments[tmp_segCount] := tmp_segValue;
    END_IF;
END_IF;

IF NOT tmp_invalid AND tmp_segCount = 4 THEN
    IF tmp_segments[1] > 255 OR tmp_segments[2] > 255 OR tmp_segments[3] > 255 OR tmp_segments[4] > 255 THEN
        tmp_invalid := TRUE;
    END_IF;
    
    IF NOT tmp_invalid THEN
        tmp_result := SHL(TO_UDINT(tmp_segments[1]), 24) OR SHL(TO_UDINT(tmp_segments[2]), 16) OR SHL(TO_UDINT(tmp_segments[3]), 8) OR TO_UDINT(tmp_segments[4]);
        ipValue := tmp_result;
    ELSE
        ipValue := 0;
    END_IF;
ELSE
    ipValue := 0;
END_IF;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)