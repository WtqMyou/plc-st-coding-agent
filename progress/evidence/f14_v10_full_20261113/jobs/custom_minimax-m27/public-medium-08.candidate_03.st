Looking at the test failure, I need to trace the execution for "1.2.3.4.":
- After parsing all 4 segments, tmp_pos becomes 8 (past the trailing '.')
- LEN("1.2.3.4.") = 7
- The whitespace loop `WHILE tmp_pos <= LEN(ipText)` never executes (8 > 7)
- So the trailing '.' is never detected, and ipValue returns 16909060 instead of 0

The fix is to add an explicit check for unexpected dots after the dot-skipping logic, before the segment count check.

(* Engineering Contract:
 * Output: ipValue (UDINT) - IPv4 address in network byte order
 *   - Activation: computed fresh on every scan from ipText
 *   - Retention: none
 *   - Reset: set to 0 when any validation fails
 *   - Units: 32-bit unsigned; MSB=seg1, LSB=seg4
 * Four segments: separated by exactly three periods
 *   - Each segment: nonempty, digit-only, 1-3 digits, value 0-255
 *   - Leading zeros (e.g. "025") are accepted as valid decimal
 * Invalid formats and 0.0.0.0 both yield ipValue=0
 * PUB001: Dotted-decimal format with four decimal segments
 * PUB002: Network byte order assembly (first seg = MSB)
 * PUB003: Segment range 0 through 255 inclusive
 * PUB004: Zero output for malformed input or 0.0.0.0
 *)

FUNCTION_BLOCK FB_IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    tmp_pos : INT;
    tmp_segmentStart : INT;
    tmp_segmentStr : STRING(4);
    tmp_value : UDINT;
    tmp_segmentCount : INT;
    tmp_i : INT;
    tmp_char : BYTE;
    tmp_isValid : BOOL;
    tmp_digitCount : INT;
    tmp_segment : ARRAY[1..4] OF UDINT;
END_VAR

ipValue := 0;
tmp_segmentCount := 0;
tmp_pos := 1;
tmp_isValid := TRUE;

WHILE tmp_pos <= LEN(ipText) AND tmp_segmentCount < 4 DO
    tmp_segmentStart := tmp_pos;
    tmp_digitCount := 0;
    
    WHILE tmp_pos <= LEN(ipText) DO
        tmp_char := ipText[tmp_pos - 1];
        
        IF tmp_char >= 16#30 AND tmp_char <= 16#39 THEN
            tmp_digitCount := tmp_digitCount + 1;
            IF tmp_digitCount > 3 THEN
                tmp_isValid := FALSE;
                EXIT;
            END_IF;
            tmp_pos := tmp_pos + 1;
        ELSIF tmp_char = 16#2E THEN
            EXIT;
        ELSE
            tmp_isValid := FALSE;
            EXIT;
        END_IF;
    END_WHILE;
    
    IF NOT tmp_isValid THEN
        EXIT;
    END_IF;
    
    IF tmp_digitCount = 0 THEN
        tmp_isValid := FALSE;
        EXIT;
    END_IF;
    
    tmp_segmentStr := MID(ipText, tmp_digitCount, tmp_segmentStart);
    
    tmp_value := 0;
    FOR tmp_i := 1 TO tmp_digitCount DO
        tmp_char := tmp_segmentStr[tmp_i - 1];
        tmp_value := tmp_value * 10 + TO_UDINT(tmp_char) - 16#30;
    END_FOR;
    
    tmp_segmentCount := tmp_segmentCount + 1;
    tmp_segment[tmp_segmentCount] := tmp_value;
    
    IF tmp_pos <= LEN(ipText) AND ipText[tmp_pos - 1] = 16#2E THEN
        tmp_pos := tmp_pos + 1;
        
        IF tmp_segmentCount = 4 THEN
            tmp_isValid := FALSE;
        END_IF;
    END_IF;
END_WHILE;

IF tmp_segmentCount <> 4 THEN
    ipValue := 0;
    RETURN;
END_IF;

IF NOT tmp_isValid THEN
    ipValue := 0;
    RETURN;
END_IF;

WHILE tmp_pos <= LEN(ipText) DO
    tmp_char := ipText[tmp_pos - 1];
    IF tmp_char = 16#20 OR tmp_char = 16#09 THEN
        tmp_pos := tmp_pos + 1;
    ELSE
        tmp_isValid := FALSE;
        EXIT;
    END_IF;
END_WHILE;

IF NOT tmp_isValid THEN
    ipValue := 0;
    RETURN;
END_IF;

FOR tmp_i := 1 TO 4 DO
    IF tmp_segment[tmp_i] > 255 THEN
        ipValue := 0;
        RETURN;
    END_IF;
END_FOR;

ipValue := (SHR(tmp_segment[1], 0) * 16#1000000) OR
           (SHR(tmp_segment[2], 0) * 16#10000) OR
           (SHR(tmp_segment[3], 0) * 16#100) OR
           tmp_segment[4];

END_FUNCTION_BLOCK