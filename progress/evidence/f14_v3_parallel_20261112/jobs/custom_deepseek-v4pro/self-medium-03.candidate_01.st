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
    preOpenBtn : BOOL := FALSE;
    preCloseBtn : BOOL := FALSE;
    risingOpen : BOOL;
    risingClose : BOOL;
    combo : BOOL;
    preCombo : BOOL;
    risingCombo : BOOL;
END_VAR

(* 计算上升沿 *)
risingOpen := openBtn AND NOT preOpenBtn;
risingClose := closeBtn AND NOT preCloseBtn;
combo := openBtn AND closeBtn;
preCombo := preOpenBtn AND preCloseBtn;
risingCombo := combo AND NOT preCombo;

IF obstacle THEN
    (* 障碍优先：任何状态立即停机并置故障 *)
    state := 3;
    motorUp := FALSE;
    motorDown := FALSE;
    errorFlag := TRUE;
ELSE
    IF state = 3 THEN
        (* 无障碍时的故障处理 *)
        IF risingCombo THEN
            (* 双键组合新上升沿：人工复位 *)
            state := 0;
            motorUp := FALSE;
            motorDown := FALSE;
            errorFlag := FALSE;
        ELSE
            (* 保持故障锁存 *)
            motorUp := FALSE;
            motorDown := FALSE;
            errorFlag := TRUE;
        END_IF;
    ELSE
        (* 非故障状态 *)
        IF (state = 1 AND openLimit) OR (state = 2 AND closeLimit) THEN
            (* 到达本方向限位：停机回IDLE *)
            state := 0;
            motorUp := FALSE;
            motorDown := FALSE;
            errorFlag := FALSE;
        ELSE
            IF state = 1 THEN
                (* 开门运行中 *)
                motorUp := TRUE;
                motorDown := FALSE;
                errorFlag := FALSE;
                (* state 保持 1 *)
            ELSIF state = 2 THEN
                (* 关门运行中 *)
                motorUp := FALSE;
                motorDown := TRUE;
                errorFlag := FALSE;
                (* state 保持 2 *)
            ELSE
                (* IDLE状态 *)
                IF risingOpen AND NOT closeBtn AND NOT openLimit THEN
                    state := 1;
                    motorUp := TRUE;
                    motorDown := FALSE;
                    errorFlag := FALSE;
                ELSIF risingClose AND NOT openBtn AND NOT closeLimit THEN
                    state := 2;
                    motorUp := FALSE;
                    motorDown := TRUE;
                    errorFlag := FALSE;
                ELSE
                    motorUp := FALSE;
                    motorDown := FALSE;
                    errorFlag := FALSE;
                    state := 0; (* 保持IDLE *)
                END_IF;
            END_IF;
        END_IF;
    END_IF;
END_IF;

(* 更新上一拍按钮状态 *)
preOpenBtn := openBtn;
preCloseBtn := closeBtn;

END_FUNCTION_BLOCK