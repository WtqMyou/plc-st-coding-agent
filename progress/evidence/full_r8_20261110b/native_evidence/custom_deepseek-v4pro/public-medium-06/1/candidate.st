FUNCTION_BLOCK FB
VAR_INPUT
    THICKNESS_FAULT : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN : BOOL;
    FaultTimestamp : DINT;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    THICKNESS_ALARM : BOOL;
    Slab_Fault_Counter : UINT;
    Slab_Runtime_Accumulator : LINT;
    Slab_Fault_History : ARRAY[0..4] OF DINT;
END_VAR
VAR
    prev_valid_fault : BOOL := FALSE;
    hold_counter : UINT := 0;
    fault_count_val : UINT := 0;
    runtime_acc_val : LINT := 0;
    history_internal : ARRAY[0..4] OF DINT;
    valid_fault : BOOL;
    rising_fault : BOOL;
    alarm_val : BOOL;
END_VAR

// 计算有效故障组合及其上升沿
valid_fault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;
rising_fault := valid_fault AND NOT prev_valid_fault;

// 报警输出计算
IF NOT THICKNESS_SIGNAL_VALID THEN
    alarm_val := FALSE;
ELSIF THICKNESS_FAULT THEN
    alarm_val := TRUE;
ELSE
    IF hold_counter < 25 THEN
        alarm_val := TRUE;
    ELSE
        alarm_val := FALSE;
    END_IF;
END_IF;

// 故障计数与历史更新（仅有效故障上升沿）
IF rising_fault THEN
    IF fault_count_val < 65535 THEN
        fault_count_val := fault_count_val + 1;
    END_IF;
    // 历史移位：先移高索引，再写新值
    history_internal[4] := history_internal[3];
    history_internal[3] := history_internal[2];
    history_internal[2] := history_internal[1];
    history_internal[1] := history_internal[0];
    history_internal[0] := FaultTimestamp;
END_IF;

// 运行时间累积：仅在合格扫描时加一
IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    runtime_acc_val := runtime_acc_val + 1;
END_IF;

// 更新保持计数器
IF NOT THICKNESS_SIGNAL_VALID THEN
    hold_counter := 0;
ELSIF THICKNESS_FAULT THEN
    hold_counter := 0;
ELSE
    IF alarm_val THEN
        hold_counter := hold_counter + 1;
    END_IF;
END_IF;

// 更新上一周期有效故障状态
prev_valid_fault := valid_fault;

// 输出赋值
THICKNESS_ALARM := alarm_val;
Slab_Fault_Counter := fault_count_val;
Slab_Runtime_Accumulator := runtime_acc_val;
Slab_Fault_History[0] := history_internal[0];
Slab_Fault_History[1] := history_internal[1];
Slab_Fault_History[2] := history_internal[2];
Slab_Fault_History[3] := history_internal[3];
Slab_Fault_History[4] := history_internal[4];
END_FUNCTION_BLOCK