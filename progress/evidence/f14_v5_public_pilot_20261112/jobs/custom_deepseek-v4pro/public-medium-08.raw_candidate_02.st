FUNCTION_BLOCK FB_IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    i : INT;
    digit : INT;
    segVal : UDINT;
    segCount : INT;
    segHasDigit : BOOL;
END_VAR

(*
ENGINEERING_CONTRACT
- ipValue: active only on valid 4-segment IPv4; recomputed every scan, no retention (PUB001/PUB003).
- ipValue reset: any malformed / nondigit / wrong segment count / out-of-range segment forces 0 immediately (PUB004).
- Same-scan priority: combinational; initializes ipValue=0, valid path overwrites; invalid path sets 0 then RETURN.
- Units/boundaries: UDINT output 0..4294967295; each segment 0..255; first segment MSB, fourth LSB (PUB003).
- segCount: local; reset to 0 each call; increments after each period and after last segment; success requires exactly 4 (PUB002).
- segHasDigit: local; reset FALSE each call and after each period; must be TRUE before every segment boundary and at end (PUB002).
- Unspecified: leading zeros accepted as plain decimal digits; no leading‑zero rejection stated.
*)

ipValue := 0;
segVal := 0;
segCount := 0;
segHasDigit := FALSE;
i := 1;

WHILE (i <= 254) AND (BYTE_TO_INT(ipText[i]) <> 0) DO
    digit := BYTE_TO_INT(ipText[i]);

    IF (digit >= 48) AND (digit <= 57) THEN
        segVal := segVal * UDINT#10 + INT_TO_UDINT(digit - INT#48);
        IF segVal > 255 THEN
            ipValue := 0;
            RETURN;
        END_IF;
        segHasDigit := TRUE;

    ELSIF digit = 46 THEN  (* '.' *)
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

    i := i + 1;
END_WHILE;

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