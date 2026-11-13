FUNCTION_BLOCK FB_IPv4Parse
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    tmp_dot1 : INT;
    tmp_dot2 : INT;
    tmp_dot3 : INT;
    tmp_seg1 : STRING(4);
    tmp_seg2 : STRING(4);
    tmp_seg3 : STRING(4);
    tmp_seg4 : STRING(4);
    tmp_val1 : UDINT;
    tmp_val2 : UDINT;
    tmp_val3 : UDINT;
    tmp_val4 : UDINT;
    tmp_valid : BOOL;
    tmp_i : INT;
    tmp_ch : BYTE;
END_VAR
(* ENGINEERING_CONTRACT
 * Parse dotted-decimal IPv4 string to 32-bit network-order UDINT.
 * Input:  ipText (STRING(254)) - dotted-decimal address
 * Output: ipValue (UDINT) - 32-bit value, network byte order; 0 if invalid
 *
 * PUB001: Parse ipText for exactly 4 decimal-digit segments separated by 3 periods
 * PUB002: Each segment value must be 0-255 inclusive
 * PUB003: Network byte order: seg1=MSB<<24, seg2<<16, seg3<<8, seg4=LSB
 * PUB004: Invalid input (wrong count, nondigit, OOR, empty segment) → ipValue=0
 *         Note: Valid address 0.0.0.0 also produces 0 per spec.
 *
 * Contract behavior: Pure combinational, no latches, no state retention.
 * Output ipValue is defined every scan from current ipText.
 *)

ipValue := 0;
tmp_valid := TRUE;

tmp_dot1 := FIND(ipText, '.');
IF tmp_dot1 < 2 OR tmp_dot1 >= LEN(ipText) THEN
    tmp_valid := FALSE;
END_IF

IF tmp_valid THEN
    tmp_dot2 := FIND(MID(ipText, LEN(ipText) - tmp_dot1, tmp_dot1 + 1), '.');
    IF tmp_dot2 < 2 OR tmp_dot2 >= (LEN(ipText) - tmp_dot1) THEN
        tmp_valid := FALSE;
    END_IF;
END_IF

IF tmp_valid THEN
    tmp_dot3 := FIND(MID(ipText, LEN(ipText) - (tmp_dot1 + tmp_dot2), tmp_dot1 + tmp_dot2 + 1), '.');
    IF tmp_dot3 < 2 THEN
        tmp_valid := FALSE;
    END_IF;
END_IF;

IF tmp_valid THEN
    tmp_seg1 := LEFT(ipText, tmp_dot1 - 1);
    tmp_seg2 := MID(ipText, tmp_dot2 - 1, tmp_dot1 + 1);
    tmp_seg3 := MID(ipText, tmp_dot3 - 1, tmp_dot1 + tmp_dot2 + 1);
    tmp_seg4 := MID(ipText, LEN(ipText) - (tmp_dot1 + tmp_dot2 + tmp_dot3), tmp_dot1 + tmp_dot2 + tmp_dot3 + 1);

    // Validate segment 1
    IF LEN(tmp_seg1) < 1 OR LEN(tmp_seg1) > 3 THEN
        tmp_valid := FALSE;
    ELSE
        tmp_val1 := 0;
        FOR tmp_i := 1 TO LEN(tmp_seg1) DO
            tmp_ch := MID(tmp_seg1, 1, tmp_i);
            IF tmp_ch < 48 OR tmp_ch > 57 THEN
                tmp_valid := FALSE;
                EXIT;
            END_IF
            tmp_val1 := tmp_val1 * 10 + TO_UDINT(tmp_ch - 48);
        END_FOR
        IF tmp_val1 > 255 THEN
            tmp_valid := FALSE;
        END_IF
    END_IF

    // Validate segment 2
    IF tmp_valid AND (LEN(tmp_seg2) < 1 OR LEN(tmp_seg2) > 3) THEN
        tmp_valid := FALSE;
    END_IF

    IF tmp_valid THEN
        tmp_val2 := 0;
        FOR tmp_i := 1 TO LEN(tmp_seg2) DO
            tmp_ch := MID(tmp_seg2, 1, tmp_i);
            IF tmp_ch < 48 OR tmp_ch > 57 THEN
                tmp_valid := FALSE;
                EXIT;
            END_IF
            tmp_val2 := tmp_val2 * 10 + TO_UDINT(tmp_ch - 48);
        END_FOR
        IF tmp_val2 > 255 THEN
            tmp_valid := FALSE;
        END_IF
    END_IF

    // Validate segment 3
    IF tmp_valid AND (LEN(tmp_seg3) < 1 OR LEN(tmp_seg3) > 3) THEN
        tmp_valid := FALSE;
    END_IF

    IF tmp_valid THEN
        tmp_val3 := 0;
        FOR tmp_i := 1 TO LEN(tmp_seg3) DO
            tmp_ch := MID(tmp_seg3, 1, tmp_i);
            IF tmp_ch < 48 OR tmp_ch > 57 THEN
                tmp_valid := FALSE;
                EXIT;
            END_IF
            tmp_val3 := tmp_val3 * 10 + TO_UDINT(tmp_ch - 48);
        END_FOR
        IF tmp_val3 > 255 THEN
            tmp_valid := FALSE;
        END_IF
    END_IF

    // Validate segment 4
    IF tmp_valid AND (LEN(tmp_seg4) < 1 OR LEN(tmp_seg4) > 3) THEN
        tmp_valid := FALSE;
    END_IF

    IF tmp_valid THEN
        tmp_val4 := 0;
        FOR tmp_i := 1 TO LEN(tmp_seg4) DO
            tmp_ch := MID(tmp_seg4, 1, tmp_i);
            IF tmp_ch < 48 OR tmp_ch > 57 THEN
                tmp_valid := FALSE;
                EXIT;
            END_IF
            tmp_val4 := tmp_val4 * 10 + TO_UDINT(tmp_ch - 48);
        END_FOR
        IF tmp_val4 > 255 THEN
            tmp_valid := FALSE;
        END_IF
    END_IF
END_IF

IF tmp_valid THEN
    ipValue := SHL(tmp_val1, 24) OR SHL(tmp_val2, 16) OR SHL(tmp_val3, 8) OR tmp_val4;
END_IF

END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)