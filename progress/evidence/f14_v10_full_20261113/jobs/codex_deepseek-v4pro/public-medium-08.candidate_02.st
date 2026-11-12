(* ENGINEERING_CONTRACT
- ipValue is recomputed from ipText on every scan; no retention/latch.
- Valid: exactly four nonempty all-digit segments, each value 0..255 inclusive.
- Network byte order: first segment is MSB, fourth segment is LSB.
- Malformed text, nondigit, empty segment, wrong segment count, or out-of-range
  value sets ipValue := 0 in that same scan.
- 0.0.0.0 is valid and produces 0.
- Leading zeros are accepted as decimal digits; their rejection is unspecified.
- Invalid-input returns leave ipValue at its preassigned value of 0.
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
    tmp_Length : INT;
    tmp_Pos : INT;
    tmp_SegmentCount : INT;
    tmp_DigitCount : INT;
    tmp_SegmentValue : UDINT;
    tmp_CharCode : UDINT;
    tmp_Accum : UDINT;
END_VAR

ipValue := 0;
tmp_Accum := 0;
tmp_Length := LEN(ipText);
tmp_Pos := 0;
tmp_SegmentCount := 0;
tmp_DigitCount := 0;
tmp_SegmentValue := 0;
tmp_CharCode := 0;

IF tmp_Length <= 0 THEN
    RETURN;
END_IF;

WHILE tmp_Pos < tmp_Length DO
    tmp_CharCode := BYTE_TO_UDINT(ipText[tmp_Pos]);

    IF (tmp_CharCode >= 48) AND (tmp_CharCode <= 57) THEN
        tmp_DigitCount := tmp_DigitCount + 1;
        tmp_SegmentValue := (tmp_SegmentValue * 10) + (tmp_CharCode - 48);

        IF tmp_SegmentValue > 255 THEN
            RETURN;
        END_IF;
    ELSIF tmp_CharCode = 46 THEN
        IF tmp_DigitCount <= 0 THEN
            RETURN;
        END_IF;

        tmp_SegmentCount := tmp_SegmentCount + 1;

        IF tmp_SegmentCount >= 4 THEN
            RETURN;
        END_IF;

        tmp_Accum := (SHL(tmp_Accum, 8)) OR tmp_SegmentValue;
        tmp_SegmentValue := 0;
        tmp_DigitCount := 0;
    ELSE
        RETURN;
    END_IF;

    tmp_Pos := tmp_Pos + 1;
END_WHILE;

IF tmp_DigitCount <= 0 THEN
    RETURN;
END_IF;

tmp_SegmentCount := tmp_SegmentCount + 1;

IF tmp_SegmentCount <> 4 THEN
    RETURN;
END_IF;

tmp_Accum := (SHL(tmp_Accum, 8)) OR tmp_SegmentValue;
ipValue := tmp_Accum;

END_FUNCTION_BLOCK