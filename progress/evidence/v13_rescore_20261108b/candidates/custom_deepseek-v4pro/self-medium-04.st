FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday : INT;
END_VAR
VAR
    accVol : REAL;
    fillState : INT; (* 0=IDLE, 1=FILLING, 2=WAIT_CONFIRM *)
    startR : BOOL;
    resetR : BOOL;
    prevStart : BOOL;
    prevReset : BOOL;
END_VAR

(* 边沿检测 *)
startR := startBtn AND NOT prevStart;
resetR := resetBtn AND NOT prevReset;

IF resetR THEN
    (* 复位优先 *)
    fillsToday := 0;
    valveOpen := FALSE;
    accVol := 0.0;
    fillState := 0;
ELSE
    CASE fillState OF
        0: (* IDLE *)
            valveOpen := FALSE;
            IF startR THEN
                valveOpen := TRUE;
                accVol := 0.0;
                fillState := 1;
            END_IF;

        1: (* FILLING *)
            accVol := accVol + flowVol;
            IF accVol >= targetVol THEN
                valveOpen := FALSE;
                fillState := 2;
            ELSE
                valveOpen := TRUE;
            END_IF;

        2: (* WAIT_CONFIRM *)
            valveOpen := FALSE;
            IF doneSensor THEN
                fillsToday := fillsToday + 1;
                fillState := 0;
            END_IF;
    END_CASE;
END_IF;

(* 更新历史 *)
prevStart := startBtn;
prevReset := resetBtn;

END_FUNCTION_BLOCK