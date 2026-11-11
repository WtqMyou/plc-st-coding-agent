FUNCTION_BLOCK FB
VAR_INPUT
    pushEn : BOOL;
    pushItem : INT;
    popEn : BOOL;
END_VAR
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR_OUTPUT
    count : INT;
    full : BOOL;
    empty : BOOL;
    head : INT;
END_VAR
VAR
    prevPushEn : BOOL := FALSE;
    prevPopEn : BOOL := FALSE;
    m_count : INT := 0;
    i : INT;
    popRising : BOOL;
    pushRising : BOOL;
END_VAR

(* 上升沿检测 *)
popRising := popEn AND NOT prevPopEn;
pushRising := pushEn AND NOT prevPushEn;

(* 先执行出队 *)
IF popRising AND (m_count > 0) THEN
    IF m_count > 1 THEN
        FOR i := 1 TO m_count - 1 DO
            fifo[i] := fifo[i + 1];
        END_FOR;
    END_IF;
    m_count := m_count - 1;
END_IF;

(* 再执行入队 *)
IF pushRising AND (m_count < 8) THEN
    m_count := m_count + 1;
    fifo[m_count] := pushItem;
END_IF;

(* 保存本次输入作为下一拍的历史 *)
prevPushEn := pushEn;
prevPopEn := popEn;

(* 输出 *)
count := m_count;
full := (m_count = 8);
empty := (m_count = 0);

IF m_count = 0 THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;
END_FUNCTION_BLOCK