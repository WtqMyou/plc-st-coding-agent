FUNCTION_BLOCK FB_IPv4Parse
    VAR_INPUT
        ipText : STRING(254);
    END_VAR
    VAR_OUTPUT
        ipValue : UDINT;
    END_VAR
    VAR
        i       : INT;
        pos     : INT;
        start   : INT;
        len     : INT;
        cnt     : INT;
        val     : INT;
        c       : CHAR;
        txtLen  : INT;
        tempPos : INT;
    END_VAR

    ipValue := 0;
    txtLen  := LEN(ipText);
    pos     := 1;
    cnt     := 0;

    // Parse up to 4 segments
    WHILE (cnt < 4) AND (pos <= txtLen) DO
        start := pos;
        len   := 0;

        // Collect digits
        WHILE (pos <= txtLen) DO
            c := MID(ipText, 1, pos);
            IF c = '.' THEN
                EXIT;
            END_IF;
            IF (c < '0') OR (c > '9') THEN
                ipValue := 0;
                RETURN;
            END_IF;
            len := len + 1;
            pos := pos + 1;
        END_WHILE;

        // Check segment length
        IF len < 1 OR len > 3 THEN
            ipValue := 0;
            RETURN;
        END_IF;

        // Parse value
        val := 0;
        tempPos := start;
        FOR i := 1 TO len DO
            c := MID(ipText, 1, tempPos);
            val := val * 10 + (c - '0');
            tempPos := tempPos + 1;
        END_FOR;

        // Range check
        IF val > 255 THEN
            ipValue := 0;
            RETURN;
        END_IF;

        // Accumulate in network byte order (MSB first)
        ipValue := (ipValue * 256) OR TO_UDINT(val);
        cnt := cnt + 1;

        // Skip dot
        IF (pos <= txtLen) AND (MID(ipText, 1, pos) = '.') THEN
            pos := pos + 1;
        END_IF;
    END_WHILE;

    // Must have exactly 4 segments
    IF cnt <> 4 THEN
        ipValue := 0;
        RETURN;
    END_IF;

    // Trailing chars (after dots/skipped) not allowed
    IF pos <= txtLen THEN
        c := MID(ipText, 1, pos);
        IF c <> ' ' AND c <> '' THEN
            ipValue := 0;
            RETURN;
        END_IF;
    END_IF;

END_FUNCTION_BLOCK