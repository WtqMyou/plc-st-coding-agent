FUNCTION_BLOCK FB
VAR_INPUT
    openBtn : BOOL;
    closeBtn : BOOL;
    openLimit : BOOL;
    closeLimit : BOOL;
    obstacle : BOOL;
END_VAR
VAR_OUTPUT
    motorUp : BOOL;
    motorDown : BOOL;
    errorFlag : BOOL;
END_VAR
VAR
    state : INT;
    openPrev : BOOL;
    closePrev : BOOL;
    openEdge : BOOL;
    closeEdge : BOOL;
    resetEdge : BOOL;
END_VAR

(* state: 0 idle, 1 opening, 2 closing, 3 latched fault. *)
resetEdge := openBtn AND closeBtn AND NOT (openPrev AND closePrev);
openEdge := openBtn AND NOT openPrev;
closeEdge := closeBtn AND NOT closePrev;
openPrev := openBtn;
closePrev := closeBtn;

IF obstacle THEN
    state := 3;
ELSE
    CASE state OF
        0:
            IF openEdge AND NOT closeBtn AND NOT openLimit THEN
                state := 1;
            ELSIF closeEdge AND NOT openBtn AND NOT closeLimit THEN
                state := 2;
            END_IF;
        1:
            IF openLimit THEN
                state := 0;
            END_IF;
        2:
            IF closeLimit THEN
                state := 0;
            END_IF;
        3:
            IF resetEdge THEN
                state := 0;
            END_IF;
    END_CASE;
END_IF;

motorUp := (state = 1) AND NOT obstacle;
motorDown := (state = 2) AND NOT obstacle;
errorFlag := (state = 3);
END_FUNCTION_BLOCK
