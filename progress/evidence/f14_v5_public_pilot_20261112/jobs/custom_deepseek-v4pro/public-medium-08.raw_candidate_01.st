FUNCTION_BLOCK FB_IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    i : INT;
    len : INT;
    digit : INT;
    segVal : UDINT;
    segCount : INT;
    segHasDigit : BOOL;
END_VAR

(*
ENGINEERING_CONTRACT
- ipValue: activated on valid 4-segment parse (PUB001/PUB003); recomputed every scan, no retention.
- ipValue reset/deactivated: malformed/non-digit/incorrect segment count/out-of-range -> 0 (PUB004); first failing check returns immediately.
- Same-scan priority: pure combinational; default 0, valid path overwrites with assembled value; any invalid path assigns 0 then RETURN.
- Units/boundaries: UDINT output 0..4294967295; each segment 0..255; first segment MSB, fourth LSB (PUB003).
- segCount: local state; reset to 0 each call; increments on completed segment; success requires exactly 4 (PUB002).
- segHasDigit: local state; reset FALSE each call and after each period; must be TRUE before every segment boundary (PUB002).
- Unspecified: leading zeros are accepted as ordinary decimal digits; no leading-zero rejection stated.
*)

ipValue := 0;
segVal := 0;
segCount := 0;
segHasDigit := FALSE;
len := LEN(ipText);

FOR i := 1 TO len DO
    digit := BYTE_TO_INT(ipText[i]);

    IF (digit >= 48) AND (digit <= 57) THEN
        segVal := segVal * UDINT#10 + INT_TO_UDINT(digit - INT#48);
        IF segVal > 255 THEN
            ipValue := 0;
            RETURN;
        END_IF;
        segHasDigit := TRUE;

    ELSIF digit = 46 THEN
        IF NOT segHasDigit THEN
            ipValue := 0;
            RETURN;
        END_IF;

        ipValue := SHL(ipValue, UINT#8);
        ipValue := ipValue OR segVal;

        segCount := segCount + 1;
        IF segCount > 3 THEN
            ipValue := 0;
            RETURN;
        END_IF;

        segVal := 0;
        segHasDigit := FALSE;

    ELSE
        ipValue := 0;
        RETURN;
    END_IF;
END_FOR;

IF NOT segHasDigit THEN
    ipValue := 0;
    RETURN;
END_IF;

ipValue := SHL(ipValue, UINT#8);
ipValue := ipValue OR segVal;
segCount := segCount + 1;

IF segCount <> 4 THEN
    ipValue := 0;
    RETURN;
END_IF;

END_FUNCTION_BLOCK