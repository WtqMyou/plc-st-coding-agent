FUNCTION_BLOCK FB_IPv4Parser
(* ENGINEERING_CONTRACT
   Output ipValue:
   - Activation: parsed and refreshed synchronously on every scan.
   - Hold: no latching; value is recomputed from ipText each scan.
   - Reset/deactivation: invalid input writes UDINT#0.
   - Same-scan priority: final overall validity wins over partial accumulation.
   - Units/bounds: UDINT 0..4294967295, segments 0..255.
   - Segment count/nonempty rules: PUB002, PUB004.
   - Byte order and assembly: PUB003, first byte at bits 24..31.
*)
(* CONTRACT_RULES [] *)
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    tmp_i : INT;
    tmp_len : INT;
    tmp_ch : USINT;
    tmp_segCount : INT;
    tmp_segLen : INT;
    tmp_shift : INT;
    tmp_segValue : UDINT;
    tmp_result : UDINT;
    tmp_valid : BOOL;
END_VAR

ipValue := UDINT#0;
tmp_valid := TRUE;
tmp_segCount := 0;
tmp_segLen := 0;
tmp_segValue := UDINT#0;
tmp_result := UDINT#0;
tmp_len := LEN(ipText);

FOR tmp_i := 0 TO tmp_len - 1 DO
    tmp_ch := BYTE_TO_USINT(ipText[tmp_i]);

    IF tmp_ch = USINT#46 THEN
        IF tmp_segLen = 0 THEN
            tmp_valid := FALSE;
            EXIT;
        END_IF;

        tmp_segCount := tmp_segCount + 1;
        IF tmp_segCount > 4 THEN
            tmp_valid := FALSE;
            EXIT;
        END_IF;

        tmp_shift := (4 - tmp_segCount) * 8;
        tmp_result := tmp_result + SHL(tmp_segValue, tmp_shift);
        tmp_segLen := 0;
        tmp_segValue := UDINT#0;
    ELSIF (tmp_ch >= USINT#48) AND (tmp_ch <= USINT#57) THEN
        tmp_segLen := tmp_segLen + 1;
        tmp_segValue := tmp_segValue * UDINT#10
                        + (USINT_TO_UDINT(tmp_ch) - UDINT#48);

        IF tmp_segValue > UDINT#255 THEN
            tmp_valid := FALSE;
            EXIT;
        END_IF;
    ELSE
        tmp_valid := FALSE;
        EXIT;
    END_IF;
END_FOR;

IF tmp_valid AND (tmp_segLen > 0) THEN
    tmp_segCount := tmp_segCount + 1;

    IF tmp_segCount = 4 THEN
        tmp_result := tmp_result + tmp_segValue;
        ipValue := tmp_result;
    ELSE
        ipValue := UDINT#0;
    END_IF;
ELSE
    ipValue := UDINT#0;
END_IF;
END_FUNCTION_BLOCK