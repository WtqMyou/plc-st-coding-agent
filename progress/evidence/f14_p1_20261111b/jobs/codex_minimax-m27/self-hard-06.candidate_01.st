FUNCTION_BLOCK FB
VAR_INPUT
    runRequest      : BOOL;          (* 运行请求 *)
    pressure        : REAL;          (* 母管压力 kPa *)
    pressureValid   : BOOL;          (* 压力变送器数据有效 *)
    fuelFlow        : REAL;          (* 燃料流量 t/h *)
    steamFlow       : REAL;          (* 蒸汽流量 t/h *)
    outletCmd       : INT;           (* 减温减压阀开度命令 % *)
    outletFeedback  : INT;           (* 减温减压阀开度反馈 % *)
    resetBtn        : BOOL;          (* 复位按钮上升沿有效 *)
END_VAR

VAR_OUTPUT
    tripLatched     : BOOL;          (* 超压跳闸自保持 *)
    fuelPermit      : BOOL;          (* 燃料许可 *)
    currentCauseMask: WORD;          (* 本周期诊断线索位掩码 *)
    latchedCauseMask: WORD;          (* 跳闸期间线索累积掩码 *)
    diagnosticActive: BOOL;          (* 存在有效诊断线索 *)
END_VAR

VAR
    prevRunRequest  : BOOL;          (* 上周期 runRequest *)
    prevResetBtn    : BOOL;          (* 上周期 resetBtn *)
    stickyCounter   : INT;           (* 阀卡滞连续周期计数 *)
END_VAR

(* 局部变量 *)
VAR
    risingReset     : BOOL;          (* 复位上升沿 *)
    stickyCondMet   : BOOL;          (* 本拍卡滞输入条件 *)
    stickyCondPrev1 : BOOL;          (* 上一拍卡滞输入条件 *)
    stickyCondPrev2 : BOOL;          (* 上两拍卡滞输入条件 *)
END_VAR

// -------------------------------------------
// 1. 边沿检测
// -------------------------------------------
risingReset := resetBtn AND NOT prevResetBtn;

// -------------------------------------------
// 2. 跳闸条件判断
// -------------------------------------------
IF runRequest AND (NOT pressureValid OR pressure >= 4500.0) THEN
    tripLatched := TRUE;
ELSIF risingReset AND NOT runRequest AND pressureValid AND pressure <= 4200.0 THEN
    tripLatched := FALSE;
END_IF

// -------------------------------------------
// 3. 燃料许可
// -------------------------------------------
fuelPermit := runRequest AND NOT tripLatched;

// -------------------------------------------
// 4. 卡滞连续判据（连续3拍）
// -------------------------------------------
(* 本拍卡滞输入条件：超压工况下阀命令>=50且反馈<=10 *)
stickyCondMet := runRequest AND pressureValid AND (pressure >= 4500.0) 
                 AND (outletCmd >= 50) AND (outletFeedback <= 10);

(* 连续性判断：需本拍及此前连续两拍均满足 *)
IF stickyCondMet THEN
    IF stickyCounter < 3 THEN
        stickyCounter := stickyCounter + 1;
    END_IF
ELSE
    stickyCounter := 0;  (* 任一条件不满足立即清零 *)
END_IF

(* 卡滞位成立条件：计数器已达3 *)
VAR
    stickyBitActive : BOOL;
END_VAR
stickyBitActive := (stickyCounter >= 3);

// -------------------------------------------
// 5. 本拍线索掩码计算
// -------------------------------------------
IF NOT runRequest THEN
    (* 无运行请求时线索为0 *)
    currentCauseMask := 0;
ELSIF NOT pressureValid THEN
    (* 变送器失效：bit0=1 *)
    currentCauseMask := 1;
ELSE
    (* 运行中且数据有效 *)
    VAR
        causeVal : INT;
    END_VAR
    causeVal := 0;
    
    (* bit1: 阀卡滞 *)
    IF stickyBitActive THEN
        causeVal := causeVal + 2;
    END_IF
    
    (* bit2: 燃烧过剩 *)
    IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
        causeVal := causeVal + 4;
    END_IF
    
    (* 超压但无其他线索：置bit3 *)
    IF (pressure >= 4500.0) AND (causeVal = 0) THEN
        causeVal := 8;
    END_IF
    
    currentCauseMask := INT_TO_WORD(causeVal);
END_IF

// -------------------------------------------
// 6. 历史线索累积
// -------------------------------------------
IF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
ELSE
    latchedCauseMask := 0;  (* 未跳闸时清零 *)
END_IF

// -------------------------------------------
// 7. 诊断有效位
// -------------------------------------------
diagnosticActive := (currentCauseMask <> 0);

// -------------------------------------------
// 8. 更新状态（供下周期边沿检测和连续性判断）
// -------------------------------------------
prevRunRequest := runRequest;
prevResetBtn   := resetBtn;

END_FUNCTION_BLOCK