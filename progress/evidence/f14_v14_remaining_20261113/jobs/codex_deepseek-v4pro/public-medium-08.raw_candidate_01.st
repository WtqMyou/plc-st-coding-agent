(* ENGINEERING_CONTRACT
ipValue is combinational and recomputed every scan; no retention (PUB003).
Activation: exactly three periods and four nonempty all-digit segments (PUB001/PUB002).
Invalid/reset: len<7, len>15, nondigit, extra/missing dot, empty segment, or value>255 => 0 (PUB001/PUB003/PUB004).
Assemble seg1<<24 | seg2<<16 | seg3<<8 | seg4 (PUB002/PUB004).
0.0.0.0 and invalid both produce 0, distinguished only by structural checks.
Malformed condition dominates valid assembly; final ipValue is 0.
Unspecified: leading zeros are accepted; whitespace/sign characters are rejected.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB_IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    tmp_len : INT;
    tmp_idx : INT;
    tmp_char : BYTE;
    tmp_digit : UDINT;
    tmp_seg_value : UDINT;
    tmp_new_value : UDINT;
    tmp_addr : UDINT;
    tmp_seg_count : INT;
    tmp_in_segment : BOOL;
    tmp_valid : BOOL;
END_VAR

tmp_len := LEN(ipText);
tmp_valid := (tmp_len >= 7) AND (tmp_len <= 15);
tmp_addr := UDINT#0;
tmp_seg_count := 0;
tmp_in_segment := FALSE;
tmp_seg_value := UDINT#0;
tmp_new_value := UDINT#0;

IF tmp_valid THEN
    FOR tmp_idx := 0 TO tmp_len - 1 DO
        tmp_char := ipText[tmp_idx];

        IF (tmp_char >= 48) AND (tmp_char <= 57) THEN
            tmp_in_segment := TRUE;
            IF tmp_seg_value <= UDINT#255 THEN
                tmp_digit := BYTE_TO_UDINT(tmp_char) - UDINT#48;
                tmp_new_value := (tmp_seg_value * UDINT#10) + tmp_digit;
                IF tmp_new_value > UDINT#255 THEN
                    tmp_seg_value := UDINT#256;
                    tmp_valid := FALSE;
                ELSE
                    tmp_seg_value := tmp_new_value;
                END_IF;
            END_IF;
        ELSIF tmp_char = 46 THEN
            IF tmp_in_segment THEN
                tmp_seg_count := tmp_seg_count + 1;
                IF tmp_seg_count > 3 THEN
                    tmp_valid := FALSE;
                END_IF;
                tmp_addr := SHL(tmp_addr, 8) OR tmp_seg_value;
                tmp_seg_value := UDINT#0;
                tmp_in_segment := FALSE;
            ELSE
                tmp_valid := FALSE;
            END_IF;
        ELSE
            tmp_valid := FALSE;
        END_IF;
    END_FOR;

    IF tmp_in_segment THEN
        tmp_addr := SHL(tmp_addr, 8) OR tmp_seg_value;
        tmp_seg_count := tmp_seg_count + 1;
        tmp_in_segment := FALSE;
    ELSE
        tmp_valid := FALSE;
    END_IF;
END_IF;

IF tmp_valid AND (tmp_seg_count = 4) THEN
    ipValue := tmp_addr;
ELSE
    ipValue := UDINT#0;
END_IF;

END_FUNCTION_BLOCK