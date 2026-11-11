(* 参考解：Dual-word edge detection（DWORD 逐位上升沿/下降沿）
   prevValue 保存上一拍的输入值，声明初值为 0（PLC 上电瞬间存储区为 0），
   因此第 1 拍等价于“相对全 0 的边沿检测”，与需求“比较两个连续的 DWORD”一致。 *)
FUNCTION_BLOCK FB_DualWordEdge
VAR_INPUT
    value : DWORD;                  (* 每个周期检查的输入字 *)
END_VAR
VAR_OUTPUT
    hasChanged : BOOL;              (* 有无任何位变化 *)
    hasRisingEdges : BOOL;          (* 有无上升沿 *)
    risingBits : DWORD;             (* 上升沿位流：某位本拍由 0 变 1 则为 1 *)
    noOfRisingBits : USINT;         (* 上升沿位数 *)
    hasFallingEdges : BOOL;         (* 有无下降沿 *)
    fallingBits : DWORD;            (* 下降沿位流：某位本拍由 1 变 0 则为 1 *)
    noOfFallingBits : USINT;        (* 下降沿位数 *)
END_VAR
VAR
    prevValue : DWORD;              (* 上一拍的输入值 *)
    tmpBits : DWORD;                (* 统计位数的移位暂存 *)
    bitCount : USINT;               (* 统计结果暂存 *)
    i : INT;                        (* 循环变量 *)
END_VAR

(* R1/R2: 按位求差。NOT 对整数是 32 位按位取反，与 DWORD 宽度一致。
   IEC 的 AND/OR 两侧都是整数时按位运算，所以这里不会退化成逻辑运算。 *)
risingBits := value AND NOT prevValue;
fallingBits := prevValue AND NOT value;

(* R3: 是否变化，以及两类边沿是否存在 *)
hasChanged := (risingBits <> 0) OR (fallingBits <> 0);
hasRisingEdges := risingBits <> 0;
hasFallingEdges := fallingBits <> 0;

(* R4: 上升沿位数——逐位右移数 1 的个数（32 位，故循环 32 次） *)
bitCount := 0;
tmpBits := risingBits;
FOR i := 1 TO 32 DO
    IF (tmpBits AND 1) <> 0 THEN
        bitCount := bitCount + 1;
    END_IF
    tmpBits := SHR(tmpBits, 1);
END_FOR
noOfRisingBits := bitCount;

(* R6: 下降沿位数，同一套逐位统计 *)
bitCount := 0;
tmpBits := fallingBits;
FOR i := 1 TO 32 DO
    IF (tmpBits AND 1) <> 0 THEN
        bitCount := bitCount + 1;
    END_IF
    tmpBits := SHR(tmpBits, 1);
END_FOR
noOfFallingBits := bitCount;

(* R5: 本拍值成为下一拍的“上一拍” *)
prevValue := value;
END_FUNCTION_BLOCK
