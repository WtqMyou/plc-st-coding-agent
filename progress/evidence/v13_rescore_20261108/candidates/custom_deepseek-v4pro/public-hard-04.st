FUNCTION_BLOCK FB
VAR_INPUT
    enqueue : BOOL;
    dequeue : BOOL;
    reset : BOOL;
    capacity : DINT;
END_VAR
VAR_OUTPUT
    elementCount : DINT;
    status : WORD;
END_VAR
VAR_IN_OUT
    item : DINT;
    buffer : ARRAY[1..4] OF DINT;
END_VAR
VAR
    head : DINT := 1;
    tail : DINT := 1;
    count : DINT := 0;
    lastEnq : BOOL := FALSE;
    lastDeq : BOOL := FALSE;
    enqRising : BOOL;
    deqRising : BOOL;
END_VAR

// 计算上升沿
enqRising := enqueue AND NOT lastEnq;
deqRising := dequeue AND NOT lastDeq;

// 更新历史值
lastEnq := enqueue;
lastDeq := dequeue;

// 复位优先
IF reset THEN
    count := 0;
    head := 1;
    tail := 1;
    status := 16#0000;
ELSE
    // 入队操作
    IF enqRising THEN
        IF count < capacity THEN
            buffer[tail] := item;
            tail := tail + 1;
            IF tail > capacity THEN
                tail := 1;
            END_IF
            count := count + 1;
            status := 16#0000;
        ELSE
            status := 16#8002; // 队列满，入队被拒绝
        END_IF
    // 出队操作
    ELSIF deqRising THEN
        IF count > 0 THEN
            item := buffer[head];
            head := head + 1;
            IF head > capacity THEN
                head := 1;
            END_IF
            count := count - 1;
            status := 16#0000;
        ELSE
            status := 16#8001; // 队列空，出队被拒绝
        END_IF
    ELSE
        status := 16#0000;
    END_IF
END_IF

// 更新输出元素个数
elementCount := count;

END_FUNCTION_BLOCK