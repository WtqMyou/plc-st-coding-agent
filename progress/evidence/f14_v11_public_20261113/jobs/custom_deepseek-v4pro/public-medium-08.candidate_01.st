(* ENGINEERING_CONTRACT
   ipValue: combinational output from current ipText; no retained/latched state.
   Activation: exactly 4 non-empty decimal segments, each value 0..255
   (PUB001, PUB003). Assemble network byte order (PUB002).
   Zero/deactivation: malformed, non-digit, wrong segment count, out-of-range,
   empty/short (<7), or length >15 characters (PUB003, PUB004).
   0.0.0.0 also produces 0.
   Same-scan: input is read once per call; no priority or reset inputs.
   Boundaries: first segment bits31..24, second bits23..16, third bits15..8,
   fourth bits7..0; UDINT result.
 *)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    tmp_len : INT;
    tmp_i : INT;
    tmp_ch : BYTE;
    tmp_segVal : UDINT;
    tmp_segCount : INT;
    tmp_digitCount : INT;
    tmp_addr : UDINT;
END_VAR

ipValue := UDINT#0;

tmp_len := LEN(ipText);
IF (tmp_len < 7) OR (tmp_len > 15) THEN
    RETURN;
END_IF;

tmp_segVal := UDINT#0;
tmp_segCount := 0;
tmp_digitCount := 0;
tmp_addr := UDINT#0;

FOR tmp_i := 0 TO (tmp_len - 1) DO
    tmp_ch := ipText[tmp_i];

    IF (tmp_ch >= BYTE#48) AND (tmp_ch <= BYTE#57) THEN
        tmp_digitCount := tmp_digitCount + 1;
        tmp_segVal := (tmp_segVal * UDINT#10) + (BYTE_TO_UDINT(tmp_ch) - UDINT#48);
        IF tmp_segVal > UDINT#255 THEN
            RETURN;
        END_IF;
    ELSIF tmp_ch = BYTE#46 THEN
        IF tmp_digitCount = 0 THEN
            RETURN;
        END_IF;
        IF tmp_segCount >= 3 THEN
            RETURN;
        END_IF;

        tmp_addr := SHL(tmp_addr, 8);
        tmp_addr := tmp_addr OR (tmp_segVal AND UDINT#255);

        tmp_segCount := tmp_segCount + 1;
        tmp_segVal := UDINT#0;
        tmp_digitCount := 0;
    ELSE
        RETURN;
    END_IF;
END_FOR;

IF (tmp_digitCount = 0) OR (tmp_segCount <> 3) THEN
    RETURN;
END_IF;

tmp_addr := SHL(tmp_addr, 8);
tmp_addr := tmp_addr OR (tmp_segVal AND UDINT#255);
ipValue := tmp_addr;

END_FUNCTION_BLOCK