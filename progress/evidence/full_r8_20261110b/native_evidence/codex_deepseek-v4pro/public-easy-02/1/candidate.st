FUNCTION_BLOCK FB
VAR_INPUT
    value : DWORD;
END_VAR
VAR_OUTPUT
    hasChanged : BOOL;
    hasRisingEdges : BOOL;
    risingBits : DWORD;
    noOfRisingBits : USINT;
    hasFallingEdges : BOOL;
    fallingBits : DWORD;
    noOfFallingBits : USINT;
END_VAR
VAR
    prevValue : DWORD;
END_VAR

risingBits := value AND (NOT prevValue);
fallingBits := prevValue AND (NOT value);

hasRisingEdges := risingBits <> DWORD#0;
hasFallingEdges := fallingBits <> DWORD#0;
hasChanged := hasRisingEdges OR hasFallingEdges;

noOfRisingBits := 0;
noOfFallingBits := 0;

IF (risingBits AND DWORD#1) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#1) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#2) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#2) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#4) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#4) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#8) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#8) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#16) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#16) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#32) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#32) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#64) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#64) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#128) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#128) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#256) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#256) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#512) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#512) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#1024) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#1024) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#2048) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#2048) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#4096) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#4096) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#8192) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#8192) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#16384) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#16384) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#32768) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#32768) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#65536) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#65536) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#131072) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#131072) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#262144) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#262144) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#524288) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#524288) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#1048576) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#1048576) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#2097152) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#2097152) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#4194304) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#4194304) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#8388608) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#8388608) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#16777216) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#16777216) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#33554432) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#33554432) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#67108864) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#67108864) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#134217728) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#134217728) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#268435456) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#268435456) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#536870912) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#536870912) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#1073741824) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#1073741824) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

IF (risingBits AND DWORD#2147483648) <> DWORD#0 THEN
    noOfRisingBits := noOfRisingBits + 1;
END_IF;
IF (fallingBits AND DWORD#2147483648) <> DWORD#0 THEN
    noOfFallingBits := noOfFallingBits + 1;
END_IF;

prevValue := value;
END_FUNCTION_BLOCK