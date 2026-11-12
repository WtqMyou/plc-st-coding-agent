FUNCTION_BLOCK IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT := 0;
END_VAR
VAR
    tmp_pos1      : INT;
    tmp_pos2      : INT;
    tmp_pos3      : INT;
    tmp_seg1      : STRING(4);
    tmp_seg2      : STRING(4);
    tmp_seg3      : STRING(4);
    tmp_seg4      : STRING(4);
    tmp_val1      : UDINT;
    tmp_val2      : UDINT;
    tmp_val3      : UDINT;
    tmp_val4      : UDINT;
    tmp_valid     : BOOL;
    tmp_i         : INT;
    tmp_char      : BYTE;
END_VAR
(* ENGINEERING_CONTRACT
  | Clause  | Output/State         | Behavior                                        |
  |---------|----------------------|-------------------------------------------------|
  | PUB001  | ipValue              | 32-bit UDINT; zero-initialized; updated once   |
  | PUB002  | ipValue              | RETENTION: holds last computed value           |
  | PUB002  | Validation path      | 4 segments via 3 period delimiters required    |
  | PUB003  | ipValue assembly     | Network byte order: seg1<<24 | seg2<<16 |      |
  |         |                      | seg3<<8 | seg4; SHL used for all shifts           |
  | PUB004  | Error output (0)     | SET: malformed, non-digit, count≠4, >255,      |
  |         |                      | or empty segment; RESET: none (latch to 0)     |
  | PUB004  | 0.0.0.0              | Produces 0; indistinguishable from error        |
  | General | Same-scan timing     | All segment extractions before any validation  |
  | General | Boundary: seg len    | 1-3 chars; non-digit check per character       |
  | General | Boundary: positions  | Periods must not be at index 0 or LEN-1        |
  | General | Type: LTIME/others   | Not applicable to this function block          |
  CONTRACT_RULES [] *)
BEGIN
    tmp_valid := TRUE;
    ipValue := 0;

    tmp_pos1 := FIND(ipText, '.');
    tmp_pos2 := FIND(ipText, '.', tmp_pos1 + 1);
    tmp_pos3 := FIND(ipText, '.', tmp_pos2 + 1);

    tmp_valid := (tmp_pos1 > 0) AND (tmp_pos2 > tmp_pos1 + 1) AND (tmp_pos3 > tmp_pos2 + 1) AND (tmp_pos3 < LEN(ipText));

    IF tmp_valid THEN
        tmp_seg1 := MID(ipText, tmp_pos1 - 1, 1);
        tmp_seg2 := MID(ipText, tmp_pos2 - tmp_pos1 - 1, tmp_pos1 + 1);
        tmp_seg3 := MID(ipText, tmp_pos3 - tmp_pos2 - 1, tmp_pos2 + 1);
        tmp_seg4 := MID(ipText, LEN(ipText) - tmp_pos3, tmp_pos3 + 1);
    END_IF;

    IF tmp_valid THEN
        tmp_valid := (LEN(tmp_seg1) > 0) AND (LEN(tmp_seg2) > 0) AND (LEN(tmp_seg3) > 0) AND (LEN(tmp_seg4) > 0);
    END_IF;

    IF tmp_valid THEN
        FOR tmp_i := 1 TO LEN(tmp_seg1) DO
            tmp_char := tmp_seg1[tmp_i - 1];
            IF (tmp_char < 48) OR (tmp_char > 57) THEN
                tmp_valid := FALSE;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_valid THEN
        FOR tmp_i := 1 TO LEN(tmp_seg2) DO
            tmp_char := tmp_seg2[tmp_i - 1];
            IF (tmp_char < 48) OR (tmp_char > 57) THEN
                tmp_valid := FALSE;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_valid THEN
        FOR tmp_i := 1 TO LEN(tmp_seg3) DO
            tmp_char := tmp_seg3[tmp_i - 1];
            IF (tmp_char < 48) OR (tmp_char > 57) THEN
                tmp_valid := FALSE;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_valid THEN
        FOR tmp_i := 1 TO LEN(tmp_seg4) DO
            tmp_char := tmp_seg4[tmp_i - 1];
            IF (tmp_char < 48) OR (tmp_char > 57) THEN
                tmp_valid := FALSE;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_valid THEN
        tmp_val1 := STRING_TO_UDINT(tmp_seg1);
        tmp_val2 := STRING_TO_UDINT(tmp_seg2);
        tmp_val3 := STRING_TO_UDINT(tmp_seg3);
        tmp_val4 := STRING_TO_UDINT(tmp_seg4);
        tmp_valid := (tmp_val1 <= 255) AND (tmp_val2 <= 255) AND (tmp_val3 <= 255) AND (tmp_val4 <= 255);
    END_IF;

    IF tmp_valid THEN
        ipValue := SHL(tmp_val1, 24) OR SHL(tmp_val2, 16) OR SHL(tmp_val3, 8) OR tmp_val4;
    END_IF;
END_FUNCTION_BLOCK