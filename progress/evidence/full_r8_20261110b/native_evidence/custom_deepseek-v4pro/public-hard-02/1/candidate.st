FUNCTION_BLOCK FB
VAR_INPUT
    processLength : USINT;
    sensor1 : BOOL;
    sensor2 : BOOL;
    sensor3 : BOOL;
    sensor4 : BOOL;
    sensor5 : BOOL;
    station1Start : BOOL;
    station2Complete : BOOL;
    station3Complete : BOOL;
    station4Complete : BOOL;
    processSequence : ARRAY[1..8] OF USINT;
END_VAR
VAR_OUTPUT
    conveyorLeft : BOOL;
    conveyorRight : BOOL;
END_VAR
VAR
    state : USINT := 0; (* 0=IDLE, 1=MOVING, 2=WAIT_PROCESS, 3=DONE *)
    currentStation : USINT := 1;
    seqIndex : USINT := 1;
    targetStation : USINT := 5;
    lastStation1Start : BOOL := FALSE;
    lastComplete2 : BOOL := FALSE;
    lastComplete3 : BOOL := FALSE;
    lastComplete4 : BOOL := FALSE;
END_VAR

(* 默认输出 *)
conveyorLeft := FALSE;
conveyorRight := FALSE;

(* 检查 processLength 有效性：若无效则强制停止并保持初始状态 *)
IF (processLength < 1) OR (processLength > 8) THEN
    state := 0;
    currentStation := 1;
    seqIndex := 1;
ELSE
    (* 状态机 *)
    IF (state = 0) OR (state = 3) THEN
        (* 启动检测：1# 传感器有料且启动按钮上升沿 *)
        IF (NOT lastStation1Start) AND station1Start AND sensor1 THEN
            seqIndex := 1;
            currentStation := 1;
            targetStation := processSequence[1];
            state := 1; (* MOVING *)
        END_IF
    ELSIF state = 1 THEN
        (* 移动中，检测目标传感器 *)
        IF (targetStation = 2) AND sensor2 THEN
            currentStation := 2;
            IF targetStation = 5 THEN
                state := 3; (* DONE *)
            ELSE
                state := 2; (* WAIT_PROCESS *)
            END_IF
        ELSIF (targetStation = 3) AND sensor3 THEN
            currentStation := 3;
            IF targetStation = 5 THEN
                state := 3;
            ELSE
                state := 2;
            END_IF
        ELSIF (targetStation = 4) AND sensor4 THEN
            currentStation := 4;
            IF targetStation = 5 THEN
                state := 3;
            ELSE
                state := 2;
            END_IF
        ELSIF (targetStation = 5) AND sensor5 THEN
            currentStation := 5;
            state := 3; (* DONE *)
        END_IF
    ELSIF state = 2 THEN
        (* 等待加工完成，检测对应完成信号上升沿 *)
        IF (currentStation = 2) AND (NOT lastComplete2) AND station2Complete THEN
            seqIndex := seqIndex + 1;
            IF seqIndex <= processLength THEN
                targetStation := processSequence[seqIndex];
                state := 1;
            ELSE
                state := 3;
            END_IF
        ELSIF (currentStation = 3) AND (NOT lastComplete3) AND station3Complete THEN
            seqIndex := seqIndex + 1;
            IF seqIndex <= processLength THEN
                targetStation := processSequence[seqIndex];
                state := 1;
            ELSE
                state := 3;
            END_IF
        ELSIF (currentStation = 4) AND (NOT lastComplete4) AND station4Complete THEN
            seqIndex := seqIndex + 1;
            IF seqIndex <= processLength THEN
                targetStation := processSequence[seqIndex];
                state := 1;
            ELSE
                state := 3;
            END_IF
        END_IF
    END_IF

    (* 设置输送方向输出 *)
    IF state = 1 THEN
        IF targetStation > currentStation THEN
            conveyorLeft := FALSE;
            conveyorRight := TRUE;
        ELSIF targetStation < currentStation THEN
            conveyorLeft := TRUE;
            conveyorRight := FALSE;
        ELSE
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
        END_IF
    ELSE
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
    END_IF
END_IF

(* 更新边沿历史 *)
lastStation1Start := station1Start;
lastComplete2 := station2Complete;
lastComplete3 := station3Complete;
lastComplete4 := station4Complete;

END_FUNCTION_BLOCK