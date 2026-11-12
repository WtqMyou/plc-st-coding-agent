(* ENGINEERING_CONTRACT
   Output ipValue:
   - Activation: exactly four nonempty decimal octets, each 0..255, separated by '.' (PUB001, PUB002).
   - Retention/hold: none; recomputed every scan from ipText.
   - Reset/deactivation: any malformed, nondigit, wrong-count, empty-segment, or out-of-range input yields 0 (PUB004).
   - Same-scan priority: one unconditional recomputation/write; valid 0.0.0.0 also yields 0.
   - Units/boundaries: UDINT; first octet occupies bits 31..24 and fourth bits 7..0 (PUB003).
   - Leading zeros are accepted as unspecified; each octet is limited to 3 decimal digits.
*)
FUNCTION_BLOCK FB_IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    strLen      : INT;
    idx         : INT;
    ch          : BYTE;
    segIndex    : INT;
    segValue    : UDINT;
    digitCount  : INT;
    accumValue  : UDINT;
END_VAR

ipValue := 0;
strLen := LEN(ipText);

IF (strLen < 7) OR (strLen > 15) THEN
    RETURN;
END_IF;

segIndex := 1;
segValue := 0;
digitCount := 0;
accumValue := 0;

FOR idx := 1 TO strLen DO
    ch := ipText[idx];

    IF (ch >= 48) AND (ch <= 57) THEN
        digitCount := digitCount + 1;
        IF digitCount > 3 THEN
            RETURN;
        END_IF;

        segValue := (segValue * 10) + (BYTE_TO_UDINT(ch) - 48);
        IF segValue > 255 THEN
            RETURN;
        END_IF;

    ELSIF ch = 46 THEN
        IF digitCount = 0 THEN
            RETURN;
        END_IF;

        IF segIndex >= 4 THEN
            RETURN;
        END_IF;

        accumValue := (accumValue * 256) + segValue;
        segIndex := segIndex + 1;
        segValue := 0;
        digitCount := 0;

    ELSE
        RETURN;
    END_IF;
END_FOR;

IF digitCount = 0 THEN
    RETURN;
END_IF;

IF segIndex <> 4 THEN
    RETURN;
END_IF;

ipValue := (accumValue * 256) + segValue;

END_FUNCTION_BLOCK