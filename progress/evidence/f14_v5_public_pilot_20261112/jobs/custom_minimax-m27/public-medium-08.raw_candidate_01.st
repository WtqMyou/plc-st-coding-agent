FUNCTION_BLOCK FB_ParseIPv4
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    idx      : UINT;
    segCount : UINT;
    curVal   : UDINT;
    inSeg    : BOOL;
    strLen   : UINT;
    ch       : BYTE;
END_VAR
// ENGINEERING_CONTRACT
// Pub Clause | Output State            | Retention        | Reset/Deactivation       | Same-Scan | Units/Boundaries
// -----------+-------------------------+------------------+--------------------------+-----------+--------------------
// PUB001     | ipValue := parsed UDINT | Holds until next | Any invalid input sets   | Sequential
//            |                         | scan             | ipValue := 0             | parse     | segments 0-255
// PUB002     | ipValue := 0            | No retention     | Returns immediately on   | on first  | 4 segments exact
//            |                         |                  | malformed char or count  | error     |
// PUB003     | ipValue := network order| No retention     | Implicit on parse error  | Sequential| MSB=seg1, LSB=seg4
//            | SHL(seg,24)|SHL(seg,16) |                  |                          | assembly  |
//            | |SHL(seg,8)|seg          |                  |                          |           |
// PUB004     | ipValue := 0            | No retention     | Returns on any validation| Sequential| 0.0.0.0 produces 0
//            |                         |                  | failure                  | on error  | (indistinguishable)
// -----------+-------------------------+------------------+--------------------------+-----------+--------------------

ipValue  := 0;
segCount := 0;
curVal   := 0;
inSeg    := FALSE;
strLen   := LEN(ipText);
idx      := 1;

WHILE idx <= strLen DO
    ch := TO_BYTE(ipText[idx]);

    IF ch >= 48 AND ch <= 57 THEN           // '0'..'9'
        curVal := curVal * 10 + (ch - 48);
        inSeg  := TRUE;
    ELSIF ch = 46 THEN                       // '.'
        IF NOT inSeg THEN
            RETURN;                         // empty segment before dot
        END_IF
        IF curVal > 255 THEN
            RETURN;                         // segment out of range
        END_IF
        segCount := segCount + 1;
        IF segCount > 3 THEN
            RETURN;                         // more than 4 segments
        END_IF
        curVal := 0;
        inSeg  := FALSE;
    ELSE
        RETURN;                             // non-digit, non-dot character
    END_IF

    idx := idx + 1;
END_WHILE

// Trailing segment after last dot
IF NOT inSeg THEN
    RETURN;                                 // empty final segment
END_IF
IF curVal > 255 THEN
    RETURN;
END_IF
segCount := segCount + 1;

IF segCount <> 4 THEN
    RETURN;                                 // fewer than 4 segments
END_IF

// Assemble in network byte order: seg1 -> bits 24-31, seg4 -> bits 0-7
ipValue := SHL(curVal, 24) OR SHL(0, 16) OR SHL(0, 8) OR curVal;
END_FUNCTION_BLOCK