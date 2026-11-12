(*
ENGINEERING_CONTRACT
ipValue: combinational UDINT, set every invocation to parsed IPv4 in network byte order (PUB002).
Invalid/malformed input, nondigit, wrong segment count, or octet >255 forces ipValue := 0 (PUB003).
No retention, no latch, no reset; each scan recomputes independently.
Same-scan priority: partial octet shifts are discarded if any later failure occurs.
Units: octets are 0..255, 8-bit; first text segment maps to bits 31..24, last to 7..0.
Leading zeros are accepted because PUB001 forbids only non-digit/empty and enforces value range.
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
    tmp_idx : INT;
    tmp_segCount : INT;      (* 1..4, current segment being parsed *)
    tmp_segVal : UDINT;      (* accumulated value of current segment *)
    tmp_segHasDigit : BOOL;  (* TRUE if current segment contains at least one digit *)
    tmp_parseOk : BOOL;      (* FALSE after any malformed condition *)
    tmp_char : INT;          (* ASCII code of current character *)
    tmp_digit : UDINT;       (* numeric value of current digit *)
END_VAR

ipValue := 0;
tmp_len := LEN(ipText);
tmp_idx := 0;
tmp_segCount := 1;
tmp_segVal := 0;
tmp_segHasDigit := FALSE;
tmp_parseOk := TRUE;

WHILE (tmp_idx < tmp_len) DO
    tmp_char := BYTE_TO_INT(ipText[tmp_idx]);

    IF (tmp_char >= 48) AND (tmp_char <= 57) THEN
        tmp_segHasDigit := TRUE;
        tmp_digit := INT_TO_UDINT(tmp_char - 48);
        tmp_segVal := tmp_segVal * TO_UDINT(10) + tmp_digit;

        IF tmp_segVal > 255 THEN
            tmp_parseOk := FALSE;
            EXIT;
        END_IF;

    ELSIF tmp_char = 46 THEN
        (* Dot: finalize current segment and advance to next *)
        IF (NOT tmp_segHasDigit) OR (tmp_segCount >= 4) THEN
            tmp_parseOk := FALSE;
            EXIT;
        END_IF;

        ipValue := SHL(ipValue, 8);
        ipValue := ipValue OR tmp_segVal;

        tmp_segCount := tmp_segCount + 1;
        tmp_segVal := 0;
        tmp_segHasDigit := FALSE;

    ELSE
        tmp_parseOk := FALSE;
        EXIT;
    END_IF;

    tmp_idx := tmp_idx + 1;
END_WHILE;

IF tmp_parseOk THEN
    IF (tmp_segCount <> 4) OR (NOT tmp_segHasDigit) THEN
        tmp_parseOk := FALSE;
    ELSE
        ipValue := SHL(ipValue, 8);
        ipValue := ipValue OR tmp_segVal;
    END_IF;
END_IF;

IF NOT tmp_parseOk THEN
    ipValue := 0;
END_IF;

END_FUNCTION_BLOCK