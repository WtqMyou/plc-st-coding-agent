FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;      (* 启动按钮，上升沿有效 *)
    resetBtn : BOOL;      (* 复位按钮，上升沿有效 *)
    doneSensor : BOOL;    (* 满瓶检测传感器 *)
    targetVol : REAL;     (* 目标灌装体积 mL *)
    flowVol : REAL;       (* 本周期累计流量增量 mL *)
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;     (* 灌装阀开命令 *)
    fillsToday : INT;     (* 今日完成瓶数 *)
END_VAR
VAR
    prevStartBtn : BOOL := FALSE;   (* 上一周期启动按钮状态 *)
    prevResetBtn : BOOL := FALSE;   (* 上一周期复位按钮状态 *)
    accumVol : REAL := 0.0;         (* 本瓶累计灌装体积 *)
    pendingConfirm : BOOL := FALSE; (* 是否待确认 *)
    prevValveOpen : BOOL := FALSE;  (* 上一周期阀门状态 *)
END_VAR

    (* 保存上一周期阀门输出状态 *)
    prevValveOpen := valveOpen;

    (* 检测复位按钮上升沿，优先处理 *)
    IF (resetBtn AND NOT prevResetBtn) THEN
        (* 复位：清零计数、累计体积，关阀，清除待确认 *)
        valveOpen := FALSE;
        fillsToday := 0;
        accumVol := 0.0;
        pendingConfirm := FALSE;
    ELSE
        (* 非复位周期 *)

        (* 处理启动按钮上升沿（仅在阀门关闭时：空闲或等待确认） *)
        IF (startBtn AND NOT prevStartBtn) AND (NOT prevValveOpen) THEN
            (* 开始新瓶：清零本瓶累计，开阀，取消上一瓶待确认 *)
            accumVol := 0.0;
            pendingConfirm := FALSE;
            valveOpen := TRUE;
        END_IF;

        (* 正在灌装：累加本拍流量，检查是否达到目标 *)
        IF valveOpen THEN
            accumVol := accumVol + flowVol;
            IF accumVol >= targetVol THEN
                valveOpen := FALSE;
                pendingConfirm := TRUE;
            END_IF;
        END_IF;

        (* 处理确认：有待确认且传感器为真，则计数 *)
        IF pendingConfirm AND doneSensor THEN
            IF fillsToday < 32767 THEN
                fillsToday := fillsToday + 1;
            END_IF;
            pendingConfirm := FALSE;
        END_IF;
    END_IF;

    (* 更新按钮前一周期状态 *)
    prevStartBtn := startBtn;
    prevResetBtn := resetBtn;

END_FUNCTION_BLOCK