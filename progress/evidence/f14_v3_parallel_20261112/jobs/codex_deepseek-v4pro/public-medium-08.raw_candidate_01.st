FUNCTION_BLOCK IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    bValid : BOOL;
    iPos : INT;
    iLength : INT;
    iCharCode : INT;
    uiCurrentValue : UDINT;
    uiDigitCount : UDINT;
    uiCompletedSegments : UDINT;
    uiAddress : UDINT;
END_VAR

ipValue := 0;
uiAddress := 0;
uiCurrentValue := 0;
uiDigitCount := 0;
uiCompletedSegments := 0;
bValid := TRUE;
iLength := LEN(ipText);

IF (iLength > 0) AND (iLength <= 15) THEN
    FOR iPos := 1 TO iLength BY 1 DO
        iCharCode := BYTE_TO_INT(ipText[iPos]);

        IF (iCharCode >= 48) AND (iCharCode <= 57) THEN
            uiCurrentValue := uiCurrentValue * 10 + INT_TO_UDINT(iCharCode - 48);
            uiDigitCount := uiDigitCount + 1;

            IF uiCurrentValue > 255 THEN
                bValid := FALSE;
                EXIT;
            END_IF;

        ELSIF iCharCode = 46 THEN
            IF (uiDigitCount = 0) OR (uiCompletedSegments >= 3) THEN
                bValid := FALSE;
                EXIT;
            END_IF;

            uiAddress := uiAddress * 256 + uiCurrentValue;
            uiCompletedSegments := uiCompletedSegments + 1;
            uiCurrentValue := 0;
            uiDigitCount := 0;

        ELSE
            bValid := FALSE;
            EXIT;
        END_IF;
    END_FOR;
ELSE
    bValid := FALSE;
END_IF;

IF bValid THEN
    IF (uiDigitCount = 0) OR (uiCompletedSegments <> 3) THEN
        bValid := FALSE;
    ELSE
        uiAddress := uiAddress * 256 + uiCurrentValue;
        ipValue := uiAddress;
    END_IF;
END_IF;

END_FUNCTION_BLOCK