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
    state : INT := 0; (* 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT *)
    openBtn_prev : BOOL := FALSE;
    closeBtn_prev : BOOL := FALSE;
    openBtn_rise : BOOL;
    closeBtn_rise : BOOL;
    bothPressed : BOOL;
    bothPressed_prev : BOOL := FALSE;
    reset_rise : BOOL;
END_VAR

(* 边沿检测 *)
openBtn_rise := openBtn AND NOT openBtn_prev;
closeBtn_rise := closeBtn AND NOT closeBtn_prev;
bothPressed := openBtn AND closeBtn;
reset_rise := bothPressed AND NOT bothPressed_prev;

(* 状态机 *)
CASE state OF
    0: (* IDLE *)
        motorUp := FALSE;
        motorDown := FALSE;
        errorFlag := FALSE;
        IF openBtn_rise AND NOT openLimit THEN
            state := 1; (* OPENING *)
        ELSIF closeBtn_rise AND NOT closeLimit THEN
            state := 2; (* CLOSING *)
        END_IF;

    1: (* OPENING *)
        motorDown := FALSE;
        errorFlag := FALSE;
        IF obstacle THEN
            motorUp := FALSE;
            state := 3; (* FAULT *)
            errorFlag := TRUE;
        ELSIF openLimit THEN
            motorUp := FALSE;
            state := 0; (* IDLE *)
        ELSE
            motorUp := TRUE;
        END_IF;

    2: (* CLOSING *)
        motorUp := FALSE;
        errorFlag := FALSE;
        IF obstacle THEN
            motorDown := FALSE;
            IF openLimit THEN
                motorUp := FALSE;
                state := 0; (* IDLE *)
            ELSE
                motorUp := TRUE;
                state := 1; (* OPENING *)
            END_IF;
        ELSIF closeLimit THEN
            motorDown := FALSE;
            state := 0; (* IDLE *)
        ELSE
            motorDown := TRUE;
        END_IF;

    3: (* FAULT *)
        motorUp := FALSE;
        motorDown := FALSE;
        errorFlag := TRUE;
        IF reset_rise AND NOT obstacle THEN
            errorFlag := FALSE;
            state := 0; (* 复位到IDLE *)
        END_IF;
END_CASE

(* 更新按钮历史 *)
openBtn_prev := openBtn;
closeBtn_prev := closeBtn;
bothPressed_prev := bothPressed;

END_FUNCTION_BLOCK