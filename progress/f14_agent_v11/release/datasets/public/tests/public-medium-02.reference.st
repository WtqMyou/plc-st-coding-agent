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
    analogValues : ARRAY[*] OF INT;
    channels : ARRAY[*] OF ST_AnalogChannel;
END_VAR
VAR
    i : DINT;
    rawBase : DINT;
    channelBase : DINT;
    idx : DINT;
    raw : INT;
    mode : INT;
    span : REAL;
END_VAR

(* R1: 处理的通道数由 count 给出，从各数组各自的下界起算，按序号一一对应 *)
rawBase := LOWER_BOUND(analogValues, 1);
channelBase := LOWER_BOUND(channels, 1);

FOR i := 0 TO count - 1 DO
    idx := channelBase + i;
    (* R2: 只处理 enable 为 TRUE 的通道，禁用通道保持原值 *)
    IF channels[idx].enable THEN
        mode := channels[idx].measuringMode;
        raw := analogValues[rawBase + i];
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
END_FOR

(* R1: analogValues 是只读输入量，全程不被改写 *)
END_FUNCTION_BLOCK
