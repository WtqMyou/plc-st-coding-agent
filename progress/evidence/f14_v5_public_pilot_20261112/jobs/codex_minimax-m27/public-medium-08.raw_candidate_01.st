FUNCTION_BLOCK IPv4_Parser
(*
ENGINEERING_CONTRACT
===================
PUB001-003: Parse dotted-decimal IPv4 string to 32-bit UDINT in network byte order
PUB004:     Output = 0 for invalid input (incl. valid 0.0.0.0 → ambiguity resolved as 0)

OUTPUT STATE:
- ipValue: activation = parsed value, retention = n/a, reset = n/a (one-shot per call)
- Units: 0–4294967295 (32-bit), zero on any malformed input per PUB004

VALIDATION (in priority order):
1. Exactly three dot separators found, each at valid position
2. No fourth dot after third (prevents extra segments)
3. Four nonempty segments, each 1–3 chars
4. Each segment contains only decimal digits (char '0'–'9')
5. Each segment numeric value within 0–255

ASSEMBLY: Network byte order per PUB003
- Segment 1 → bits[31:24] (MSB)
- Segment 2 → bits[23:16]
- Segment 3 → bits[15:8]
- Segment 4 → bits[7:0] (LSB)

SCAN BEHAVIOR: Deterministic single-scan parse, no latching, no edge triggers
*)

VAR_INPUT
    ipText : STRING(254);
END_VAR

VAR_OUTPUT
    ipValue : UDINT := 0;
END_VAR

VAR
    dotPos1   : INT;
    dotPos2   : INT;
    dotPos3   : INT;
    textLen   : INT;
    segLen    : INT;
    seg1      : STRING(3);
    seg2      : STRING(3);
    seg3      : STRING(3);
    seg4      : STRING(3);
    val1      : UDINT;
    val2      : UDINT;
    val3      : UDINT;
    val4      : UDINT;
    i         : INT;
    charVal   : BYTE;
    valid     : BOOL;
END_VAR

    // Locate the three period separators
    dotPos1 := FIND(ipText, '.');
    dotPos2 := FIND(ipText, '.', dotPos1 + 1);
    dotPos3 := FIND(ipText, '.', dotPos2 + 1);

    // PUB002: must have exactly three dots at valid positions
    IF dotPos1 <= 0 OR dotPos2 <= 0 OR dotPos3 <= 0 THEN
        ipValue := 0;
        RETURN;
    END_IF;

    // No fourth dot allowed
    textLen := LEN(ipText);
    IF FIND(ipText, '.', dotPos3 + 1) <> 0 THEN
        ipValue := 0;
        RETURN;
    END_IF;

    // Segment 1: positions 1 to dotPos1-1 (length = dotPos1-1)
    segLen := dotPos1 - 1;
    IF segLen < 1 OR segLen > 3 THEN
        ipValue := 0;
        RETURN;
    END_IF;
    seg1 := MID(ipText, segLen, 1);
    valid := TRUE;
    FOR i := 1 TO segLen DO
        charVal := TO_BYTE(MID(seg1, 1, i));
        IF charVal < 48 OR charVal > 57 THEN
            valid := FALSE;
            EXIT;
        END_IF;
    END_FOR;
    IF NOT valid THEN
        ipValue := 0;
        RETURN;
    END_IF;
    val1 := TO_UDINT(seg1);
    IF val1 > 255 THEN
        ipValue := 0;
        RETURN;
    END_IF;

    // Segment 2: positions dotPos1+1 to dotPos2-1
    segLen := dotPos2 - dotPos1 - 1;
    IF segLen < 1 OR segLen > 3 THEN
        ipValue := 0;
        RETURN;
    END_IF;
    seg2 := MID(ipText, segLen, dotPos1 + 1);
    valid := TRUE;
    FOR i := 1 TO segLen DO
        charVal := TO_BYTE(MID(seg2, 1, i));
        IF charVal < 48 OR charVal > 57 THEN
            valid := FALSE;
            EXIT;
        END_IF;
    END_FOR;
    IF NOT valid THEN
        ipValue := 0;
        RETURN;
    END_IF;
    val2 := TO_UDINT(seg2);
    IF val2 > 255 THEN
        ipValue := 0;
        RETURN;
    END_IF;

    // Segment 3: positions dotPos2+1 to dotPos3-1
    segLen := dotPos3 - dotPos2 - 1;
    IF segLen < 1 OR segLen > 3 THEN
        ipValue := 0;
        RETURN;
    END_IF;
    seg3 := MID(ipText, segLen, dotPos2 + 1);
    valid := TRUE;
    FOR i := 1 TO segLen DO
        charVal := TO_BYTE(MID(seg3, 1, i));
        IF charVal < 48 OR charVal > 57 THEN
            valid := FALSE;
            EXIT;
        END_IF;
    END_FOR;
    IF NOT valid THEN
        ipValue := 0;
        RETURN;
    END_IF;
    val3 := TO_UDINT(seg3);
    IF val3 > 255 THEN
        ipValue := 0;
        RETURN;
    END_IF;

    // Segment 4: positions dotPos3+1 to end
    segLen := textLen - dotPos3;
    IF segLen < 1 OR segLen > 3 THEN
        ipValue := 0;
        RETURN;
    END_IF;
    seg4 := MID(ipText, segLen, dotPos3 + 1);
    valid := TRUE;
    FOR i := 1 TO segLen DO
        charVal := TO_BYTE(MID(seg4, 1, i));
        IF charVal < 48 OR charVal > 57 THEN
            valid := FALSE;
            EXIT;
        END_IF;
    END_FOR;
    IF NOT valid THEN
        ipValue := 0;
        RETURN;
    END_IF;
    val4 := TO_UDINT(seg4);
    IF val4 > 255 THEN
        ipValue := 0;
        RETURN;
    END_IF;

    // PUB003: Assemble in network byte order (MSB first)
    ipValue := SHL(val1, 24) OR SHL(val2, 16) OR SHL(val3, 8) OR val4;

END_FUNCTION_BLOCK