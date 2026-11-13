FUNCTION_BLOCK IPv4_Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    tmp_pos : UDINT;
    tmp_seg : STRING(4);
    tmp_val : UDINT;
    tmp_byte0 : UDINT;
    tmp_byte1 : UDINT;
    tmp_byte2 : UDINT;
    tmp_byte3 : UDINT;
    tmp_byte_index : UDINT;
    tmp_text_len : UDINT;
    tmp_char : BYTE;
    tmp_seg_len : UDINT;
END_VAR

(*
ENGINEERING_CONTRACT
PUB001: Four nonempty decimal-digit segments separated by periods
PUB002: Each segment 0-255; invalid/empty → ipValue=0
PUB003: Network byte order: seg1=MSB(31:24), seg4=LSB(7:0)
PUB004: Valid address 0.0.0.0 also produces 0 (boundary case)
*)

tmp_text_len := LEN(ipText);
IF tmp_text_len = 0 OR tmp_text_len > 15 THEN
    ipValue := 0;
    RETURN;
END_IF;

tmp_pos := 1;
tmp_byte_index := 0;

WHILE tmp_byte_index < 4 DO
    tmp_seg := '';
    tmp_seg_len := 0;
    
    WHILE tmp_pos <= tmp_text_len DO
        tmp_char := ipText[tmp_pos - 1];
        IF tmp_char = 46 THEN
            EXIT;
        END_IF
        IF tmp_char < 48 OR tmp_char > 57 THEN
            ipValue := 0;
            RETURN;
        END_IF
        tmp_seg := CONCAT(tmp_seg, CHR(tmp_char));
        tmp_seg_len := tmp_seg_len + 1;
        tmp_pos := tmp_pos + 1;
    END_WHILE
    
    IF tmp_seg_len = 0 OR tmp_seg_len > 3 THEN
        ipValue := 0;
        RETURN;
    END_IF
    
    tmp_val := STRING_TO_UDINT(tmp_seg);
    IF tmp_val > 255 THEN
        ipValue := 0;
        RETURN;
    END_IF
    
    IF tmp_byte_index = 0 THEN
        tmp_byte0 := tmp_val;
    ELSIF tmp_byte_index = 1 THEN
        tmp_byte1 := tmp_val;
    ELSIF tmp_byte_index = 2 THEN
        tmp_byte2 := tmp_val;
    ELSIF tmp_byte_index = 3 THEN
        tmp_byte3 := tmp_val;
    END_IF
    
    tmp_byte_index := tmp_byte_index + 1;
    
    IF tmp_pos > tmp_text_len THEN
        EXIT;
    END_IF
    
    IF ipText[tmp_pos - 1] <> 46 THEN
        ipValue := 0;
        RETURN;
    END_IF
    
    tmp_pos := tmp_pos + 1;
END_WHILE;

IF tmp_byte_index <> 4 THEN
    ipValue := 0;
    RETURN;
END_IF;

ipValue := (tmp_byte0 * 16777216) OR (tmp_byte1 * 65536) OR (tmp_byte2 * 256) OR tmp_byte3;

END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)