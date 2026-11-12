FUNCTION_BLOCK FillingLineControl
VAR_INPUT
    bottleSensor : BOOL;
    cleaningConfirmButton : BOOL;
    fillingConfirmButton : BOOL;
    cappingConfirmButton : BOOL;
    packingConfirmButton : BOOL;
    finishedButton : BOOL;
END_VAR

VAR_OUTPUT
    Pump_Motor : BOOL;
    Filling_Valve : BOOL;
    Capping_Machine : BOOL;
    Packing_Machine : BOOL;
    Completion_Light : BOOL;
END_VAR

VAR
    stepState : INT := 0;
    
    lastBottleSensor : BOOL := FALSE;
    lastCleaningConfirmButton : BOOL := FALSE;
    lastFillingConfirmButton : BOOL := FALSE;
    lastCappingConfirmButton : BOOL := FALSE;
    lastPackingConfirmButton : BOOL := FALSE;
    lastFinishedButton : BOOL := FALSE;
    
    bottleSensorR : BOOL;
    cleaningConfirmR : BOOL;
    fillingConfirmR : BOOL;
    cappingConfirmR : BOOL;
    packingConfirmR : BOOL;
    finishedR : BOOL;
END_VAR

(* 上升沿检测 *)
bottleSensorR := bottleSensor AND NOT lastBottleSensor;
cleaningConfirmR := cleaningConfirmButton AND NOT lastCleaningConfirmButton;
fillingConfirmR := fillingConfirmButton AND NOT lastFillingConfirmButton;
cappingConfirmR := cappingConfirmButton AND NOT lastCappingConfirmButton;
packingConfirmR := packingConfirmButton AND NOT lastPackingConfirmButton;
finishedR := finishedButton AND NOT lastFinishedButton;

(* 步骤状态机 *)
CASE stepState OF
    0: (* 等待瓶子到达 *)
        IF bottleSensorR THEN
            stepState := 1;
        END_IF;
        
    1: (* 清洁 *)
        IF cleaningConfirmR THEN
            stepState := 2;
        END_IF;
        
    2: (* 填充 *)
        IF fillingConfirmR THEN
            stepState := 3;
        END_IF;
        
    3: (* 封盖 *)
        IF cappingConfirmR THEN
            stepState := 4;
        END_IF;
        
    4: (* 包装 *)
        IF packingConfirmR THEN
            stepState := 5;
        END_IF;
        
    5: (* 完成指示 *)
        IF finishedR THEN
            stepState := 0;
        END_IF;
END_CASE;

(* 输出分配 *)
Pump_Motor := (stepState = 1);
Filling_Valve := (stepState = 2);
Capping_Machine := (stepState = 3);
Packing_Machine := (stepState = 4);
Completion_Light := (stepState = 5);

(* 更新上一次输入状态 *)
lastBottleSensor := bottleSensor;
lastCleaningConfirmButton := cleaningConfirmButton;
lastFillingConfirmButton := fillingConfirmButton;
lastCappingConfirmButton := cappingConfirmButton;
lastPackingConfirmButton := packingConfirmButton;
lastFinishedButton := finishedButton;

END_FUNCTION_BLOCK