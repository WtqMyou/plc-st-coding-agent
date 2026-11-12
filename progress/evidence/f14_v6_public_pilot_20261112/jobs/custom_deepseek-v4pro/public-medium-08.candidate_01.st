(* ENGINEERING_CONTRACT
 * Output ipValue: computed each scan (PUB001/PUB003); no retention.
 * Reset/deactivation: ipValue := 0 for malformed, nondigit, wrong segment count, or range error (PUB004).
 * Same-scan priority: only ipText drives ipValue; no competing commands or latches.
 * Units/boundaries: each decimal segment 0..255 (PUB002); assembled network byte order into UDINT (PUB003).
 * Valid 0.0.0.0 yields UDINT 0, indistinguishable from invalid by value only.
 * Leading zeros are accepted; PUB002 defines value range and nonempty digits, no max length.
 * String indexing is zero-based BYTE; ASCII digits 48..57 and dot 46 are the only accepted characters.
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
    local_i : INT;
    local_len : INT;
    local_code : INT;
    local_digit_count : INT;
    local_dot_count : INT;
    local_segment_value : UDINT;
    local_segment_invalid : BOOL;
    local_valid : BOOL;
    local_segments : ARRAY[0..3] OF UDINT;
END_VAR

ipValue := 0;
local_valid := TRUE;
local_len := LEN(ipText);
local_digit_count := 0;
local_dot_count := 0;
local_segment_value := 0;
local_segment_invalid := FALSE;
local_segments[0] := 0;
local_segments[1] := 0;
local_segments[2] := 0;
local_segments[3] := 0;

IF local_len = 0 THEN
    local_valid := FALSE;
END_IF;

FOR local_i := 0 TO local_len - 1 DO
    local_code := BYTE_TO_INT(ipText[local_i]);

    IF (local_code >= 48) AND (local_code <= 57) THEN
        local_digit_count := local_digit_count + 1;
        IF NOT local_segment_invalid THEN
            local_segment_value := local_segment_value * UDINT#10 + INT_TO_UDINT(local_code - 48);
            IF local_segment_value > UDINT#255 THEN
                local_segment_invalid := TRUE;
                local_valid := FALSE;
            END_IF;
        END_IF;

    ELSIF local_code = 46 THEN
        IF (local_digit_count = 0) OR local_segment_invalid OR (local_dot_count >= 3) THEN
            local_valid := FALSE;
        ELSE
            local_segments[local_dot_count] := local_segment_value;
        END_IF;

        local_dot_count := local_dot_count + 1;
        local_digit_count := 0;
        local_segment_value := 0;
        local_segment_invalid := FALSE;

    ELSE
        local_valid := FALSE;
    END_IF;
END_FOR;

IF local_valid AND (local_digit_count > 0) AND (NOT local_segment_invalid) AND (local_dot_count = 3) THEN
    local_segments[3] := local_segment_value;
    ipValue := SHL(local_segments[0], 24)
               OR SHL(local_segments[1], 16)
               OR SHL(local_segments[2], 8)
               OR local_segments[3];
ELSE
    ipValue := 0;
END_IF;

END_FUNCTION_BLOCK