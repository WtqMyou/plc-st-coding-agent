(* public-hard-02 Flexible Processing Control
   1# 上料 / 2#~4# 加工 / 5# 出库。工序序列由 processSequence + processLength 给出，
   processLength 从 processSequence[1] 起算，末项由 caller 保证是 5# 出库站。
   内部状态机 phase：0=空闲/待料，1=输送中，2=等当前加工工位完成信号。 *)

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
    phase : INT;          (* 0 空闲；1 输送中；2 等加工完成 *)
    idx : INT;            (* 当前执行到 processSequence 的第几项 *)
    curStation : INT;     (* 产品当前所在工位 *)
    dstStation : INT;     (* 本段输送的目标工位 *)
    lenNow : INT;
    dstOK : BOOL;
    arrived : BOOL;
    startEdge : BOOL;
    startPrev : BOOL;
    compEdge : BOOL;
    comp2Prev : BOOL;
    comp3Prev : BOOL;
    comp4Prev : BOOL;
END_VAR

(* R1/R2: 启动按钮上升沿 + 1# 有料才启动；序列长度必须落在 1..8 *)
startEdge := station1Start AND NOT startPrev;
startPrev := station1Start;
lenNow := USINT_TO_INT(processLength);

(* 加工完成信号按上升沿消费；每拍都刷新历史值，避免边沿被相位切换吃掉 *)
compEdge := FALSE;
IF phase = 2 THEN
    IF curStation = 2 THEN
        compEdge := station2Complete AND NOT comp2Prev;
    ELSIF curStation = 3 THEN
        compEdge := station3Complete AND NOT comp3Prev;
    ELSIF curStation = 4 THEN
        compEdge := station4Complete AND NOT comp4Prev;
    END_IF;
END_IF;
comp2Prev := station2Complete;
comp3Prev := station3Complete;
comp4Prev := station4Complete;

conveyorLeft := FALSE;
conveyorRight := FALSE;

(* R1: 上料工位有料 + 按下启动 → 查第一个工序号，当拍就启动输送带 *)
IF phase = 0 THEN
    IF sensor1 AND startEdge THEN
        IF (lenNow >= 1) AND (lenNow <= 8) THEN
            dstStation := USINT_TO_INT(processSequence[1]);
            dstOK := (dstStation >= 2) AND (dstStation <= 5);
            IF dstOK THEN
                idx := 1;
                curStation := 1;
                phase := 1;
            END_IF;
        END_IF;
    END_IF;
END_IF;

(* R4: 收到当前工位完成信号 → 查下一个工序号，当拍转向继续输送 *)
IF phase = 2 THEN
    IF compEdge THEN
        idx := idx + 1;
        IF (idx > lenNow) OR (idx > 8) THEN
            (* 非法序列（末项不是 5#）的保护：不再读数组下标，直接停机 *)
            phase := 0;
        ELSE
            dstStation := USINT_TO_INT(processSequence[idx]);
            dstOK := (dstStation >= 2) AND (dstStation <= 5);
            IF dstOK THEN
                phase := 1;
            ELSE
                phase := 0;
            END_IF;
        END_IF;
    END_IF;
END_IF;

(* R3/R5: 按 "目标工位 vs 当前工位" 决定方向；只看目标工位传感器判到位 *)
IF phase = 1 THEN
    IF dstStation > curStation THEN
        conveyorRight := TRUE;
    ELSIF dstStation < curStation THEN
        conveyorLeft := TRUE;
    END_IF;
    arrived := FALSE;
    IF dstStation = 2 THEN
        arrived := sensor2;
    ELSIF dstStation = 3 THEN
        arrived := sensor3;
    ELSIF dstStation = 4 THEN
        arrived := sensor4;
    ELSIF dstStation = 5 THEN
        arrived := sensor5;
    END_IF;
    IF arrived THEN
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
        curStation := dstStation;
        IF dstStation = 5 THEN
            (* R5: 送到 5# 出库站，一个产品的流程结束 *)
            phase := 0;
        ELSE
            (* R4: 停在该工位，等它给出加工完成信号 *)
            phase := 2;
        END_IF;
    END_IF;
END_IF;
END_FUNCTION_BLOCK
