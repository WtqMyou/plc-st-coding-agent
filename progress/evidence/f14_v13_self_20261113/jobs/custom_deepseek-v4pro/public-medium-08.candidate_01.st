FUNCTION_BLOCK IPv4Parser
(* ENGINEERING_CONTRACT
   Output ipValue: combinational UDINT, written every invocation from current ipText.
   Activation: all four segments valid (PUB001-PUB004). Retention: none; invalid sets 0 same scan.
   Reset: malformed/nondigit/incorrect count/out-of-range sets 0 (PUB001/PUB002/PUB003).
   Same-scan priority: final parse result only; no latches.
   Units/boundaries: network byte order UDINT, first octet bits 31..24, fourth octet bits 7..0; each octet 0..255.
*)
(* CONTRACT_RULES [] *)
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    tmp_len : INT;
    tmp_i : INT;
    tmp_c : BYTE;
    tmp_digit : INT;
    tmp_val : UDINT;
    tmp_digits_in_seg : INT;
    tmp_seg_count : INT;
    tmp_ok : BOOL;
    tmp_result : UDINT;
END_VAR

tmp_len := LEN(ipText);

IF (tmp_len < 7) OR (tmp_len > 15) THEN
    ipValue := UDINT#0;
    RETURN;
END_IF;

tmp_i := 0;
tmp_seg_count := 0;
tmp_digits_in_seg := 0;
tmp_val := UDINT#0;
tmp_result := UDINT#0;
tmp_ok := TRUE;

WHILE (tmp_i < tmp_len) AND tmp_ok DO
    tmp_c := ipText[tmp_i];

    IF (tmp_c >= BYTE#48) AND (tmp_c <= BYTE#57) THEN
        tmp_digit := BYTE_TO_INT(tmp_c) - 48;

        IF tmp_val > UDINT#25 THEN
            tmp_ok := FALSE;
        ELSE
            tmp_val := (tmp_val * UDINT#10) + INT_TO_UDINT(tmp_digit);
            tmp_digits_in_seg := tmp_digits_in_seg + 1;
        END_IF;

    ELSIF tmp_c = BYTE#46 THEN
        IF (tmp_digits_in_seg = 0) OR (tmp_val > UDINT#255) OR (tmp_seg_count >= 3) THEN
            tmp_ok := FALSE;
        ELSE
            tmp_result := SHL(tmp_result, 8);
            tmp_result := tmp_result OR tmp_val;

            tmp_seg_count := tmp_seg_count + 1;
            tmp_val := UDINT#0;
            tmp_digits_in_seg := 0;
        END_IF;

    ELSE
        tmp_ok := FALSE;
    END_IF;

    tmp_i := tmp_i + 1;
END_WHILE;

IF tmp_ok THEN
    IF (tmp_digits_in_seg = 0) OR (tmp_val > UDINT#255) OR (tmp_seg_count <> 3) THEN
        tmp_ok := FALSE;
    END_IF;
END_IF;

IF tmp_ok THEN
    tmp_result := SHL(tmp_result, 8);
    tmp_result := tmp_result OR tmp_val;
    ipValue := tmp_result;
ELSE
    ipValue := UDINT#0;
END_IF;

END_FUNCTION_BLOCK