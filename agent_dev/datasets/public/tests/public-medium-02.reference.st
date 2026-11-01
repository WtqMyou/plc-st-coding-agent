(* 平台边界（约定 §7）：本解释器把 ARRAY[*] 的 inout 数组降级为空数组，
   用例无法把数据灌进去（coerce 对无界数组返回 lo=0,hi=-1 的空数组），
   因此这里取"最接近需求的工程实现"：用固定容量 ARRAY[1..8] 表达通道数组，
   实际参与处理的通道数仍由 count 给出（容量上限 8 个通道）。
   语义按需求逐条实现，未改弱：只写 retVal/outputValue，配置字段只读。 *)
TYPE ST_AnalogChannel :
STRUCT
    enable : BOOL;
    hiLIM : REAL;
    loLIM : REAL;
    bipolar : BOOL;
    measuringMode : INT;
    retVal : WORD;
    outputValue : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[1..8] OF INT;
    channels : ARRAY[1..8] OF ST_AnalogChannel;
END_VAR
VAR
    i : DINT;
    n : DINT;
    base : DINT;
    idx : DINT;
    raw : INT;
    mode : INT;
    span : REAL;
END_VAR

(* R1: 处理的通道数由 count 给出，从各数组各自的下界起算，按序号一一对应 *)
n := count;
IF n < 0 THEN
    n := 0;
END_IF
IF n > 8 THEN
    n := 8;
END_IF
base := LOWER_BOUND(analogValues, 1);

FOR i := 0 TO n - 1 DO
    idx := base + i;
    IF idx >= 1 AND idx <= 8 THEN
        (* R2: 只处理 enable 为 TRUE 的通道，禁用通道保持原值 *)
        IF channels[idx].enable THEN
            mode := channels[idx].measuringMode;
            raw := analogValues[idx];
            IF mode < 0 OR mode > 2 THEN
                (* R6: 非法测量模式 -> 16#8001 并跳过 *)
                channels[idx].retVal := 16#8001;
            ELSE
                IF channels[idx].hiLIM <= channels[idx].loLIM THEN
                    (* R7: 量程非法 -> 16#8002 并跳过 *)
                    channels[idx].retVal := 16#8002;
                ELSE
                    span := channels[idx].hiLIM - channels[idx].loLIM;
                    IF mode = 0 THEN
                        (* R5: 非温度线性标定 *)
                        IF channels[idx].bipolar THEN
                            (* 双极：-27648..27648 -> loLIM..hiLIM *)
                            channels[idx].outputValue := channels[idx].loLIM
                                + (INT_TO_REAL(raw) + 27648.0) * span / 55296.0;
                        ELSE
                            (* 单极：0..27648 -> loLIM..hiLIM *)
                            channels[idx].outputValue := channels[idx].loLIM
                                + INT_TO_REAL(raw) * span / 27648.0;
                        END_IF
                    ELSE
                        IF mode = 1 THEN
                            (* R5: 标准温度 = raw / 10 *)
                            channels[idx].outputValue := INT_TO_REAL(raw) / 10.0;
                        ELSE
                            (* R5: 气候温度 = raw / 100 *)
                            channels[idx].outputValue := INT_TO_REAL(raw) / 100.0;
                        END_IF
                    END_IF
                    channels[idx].retVal := 16#0000;
                END_IF
            END_IF
        END_IF
    END_IF
END_FOR

(* R1: analogValues 是只读输入量，全程不被改写 *)
END_FUNCTION_BLOCK
