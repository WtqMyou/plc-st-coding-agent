(* ENGINEERING_CONTRACT
   PUB001: Parse dotted-decimal IPv4, validate 4 numeric segments 0-255
   PUB002: Network byte order assembly (MSB=first segment)
   PUB003: Invalid input → ipValue=0 (malformed, nondigit, wrong count, OOR)
   PUB004: Valid 0.0.0.0 also produces 0 (by assembly)
   
   State retention: None (stateless function block)
   Reset behavior: None (no reset input specified)
   First scan: Same as subsequent (no edge memory)
   
   Bug fix: Reject empty segments (consecutive delimiters like "1..2.3")
   by tracking nonempty digit accumulation per segment
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK IPv4_Parse
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT := 0;
END_VAR
VAR
    tmp_pos : UDINT;
    tmp_seg_idx : UDINT;
    tmp_char : BYTE;
    tmp_seg_val : UDINT;
    tmp_result : UDINT;
    tmp_seg_nonempty : BOOL;
END_VAR

tmp_pos := 0;
tmp_seg_idx := 0;
tmp_result := 0;
tmp_seg_val := 0;
tmp_seg_nonempty := FALSE;

WHILE tmp_pos < LEN(ipText) DO
    tmp_char := ipText[tmp_pos];
    
    IF tmp_char >= 48 AND tmp_char <= 57 THEN
        tmp_seg_val := tmp_seg_val * 10 + TO_UDINT(tmp_char - 48);
        
        IF tmp_seg_val > 255 THEN
            ipValue := 0;
            RETURN;
        END_IF;
        
        tmp_seg_nonempty := TRUE;
        tmp_pos := tmp_pos + 1;
        
    ELSIF tmp_char = 46 THEN
        
        IF NOT tmp_seg_nonempty THEN
            ipValue := 0;
            RETURN;
        END_IF;
        
        IF tmp_seg_idx >= 3 THEN
            ipValue := 0;
            RETURN;
        END_IF;
        
        CASE tmp_seg_idx OF
            0: tmp_result := SHL(tmp_seg_val, 24);
            1: tmp_result := tmp_result OR SHL(tmp_seg_val, 16);
            2: tmp_result := tmp_result OR SHL(tmp_seg_val, 8);
        END_CASE;
        
        tmp_seg_idx := tmp_seg_idx + 1;
        tmp_seg_val := 0;
        tmp_seg_nonempty := FALSE;
        tmp_pos := tmp_pos + 1;
    ELSE
        
        ipValue := 0;
        RETURN;
    END_IF;
END_WHILE;

IF tmp_seg_idx <> 3 THEN
    ipValue := 0;
ELSE
    tmp_result := tmp_result OR tmp_seg_val;
    ipValue := tmp_result;
END_IF;

END_FUNCTION_BLOCK