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
    prev_value : DWORD := 0;
    sumRising : DWORD;
    sumFalling : DWORD;
END_VAR

risingBits := value AND (NOT prev_value);
fallingBits := prev_value AND (NOT value);

hasRisingEdges := (risingBits <> 0);
hasFallingEdges := (fallingBits <> 0);
hasChanged := hasRisingEdges OR hasFallingEdges;

sumRising := (SHR(risingBits, 0) AND 1) + (SHR(risingBits, 1) AND 1) + (SHR(risingBits, 2) AND 1) + (SHR(risingBits, 3) AND 1) + (SHR(risingBits, 4) AND 1) + (SHR(risingBits, 5) AND 1) + (SHR(risingBits, 6) AND 1) + (SHR(risingBits, 7) AND 1) + (SHR(risingBits, 8) AND 1) + (SHR(risingBits, 9) AND 1) + (SHR(risingBits, 10) AND 1) + (SHR(risingBits, 11) AND 1) + (SHR(risingBits, 12) AND 1) + (SHR(risingBits, 13) AND 1) + (SHR(risingBits, 14) AND 1) + (SHR(risingBits, 15) AND 1) + (SHR(risingBits, 16) AND 1) + (SHR(risingBits, 17) AND 1) + (SHR(risingBits, 18) AND 1) + (SHR(risingBits, 19) AND 1) + (SHR(risingBits, 20) AND 1) + (SHR(risingBits, 21) AND 1) + (SHR(risingBits, 22) AND 1) + (SHR(risingBits, 23) AND 1) + (SHR(risingBits, 24) AND 1) + (SHR(risingBits, 25) AND 1) + (SHR(risingBits, 26) AND 1) + (SHR(risingBits, 27) AND 1) + (SHR(risingBits, 28) AND 1) + (SHR(risingBits, 29) AND 1) + (SHR(risingBits, 30) AND 1) + (SHR(risingBits, 31) AND 1);
noOfRisingBits := sumRising;

sumFalling := (SHR(fallingBits, 0) AND 1) + (SHR(fallingBits, 1) AND 1) + (SHR(fallingBits, 2) AND 1) + (SHR(fallingBits, 3) AND 1) + (SHR(fallingBits, 4) AND 1) + (SHR(fallingBits, 5) AND 1) + (SHR(fallingBits, 6) AND 1) + (SHR(fallingBits, 7) AND 1) + (SHR(fallingBits, 8) AND 1) + (SHR(fallingBits, 9) AND 1) + (SHR(fallingBits, 10) AND 1) + (SHR(fallingBits, 11) AND 1) + (SHR(fallingBits, 12) AND 1) + (SHR(fallingBits, 13) AND 1) + (SHR(fallingBits, 14) AND 1) + (SHR(fallingBits, 15) AND 1) + (SHR(fallingBits, 16) AND 1) + (SHR(fallingBits, 17) AND 1) + (SHR(fallingBits, 18) AND 1) + (SHR(fallingBits, 19) AND 1) + (SHR(fallingBits, 20) AND 1) + (SHR(fallingBits, 21) AND 1) + (SHR(fallingBits, 22) AND 1) + (SHR(fallingBits, 23) AND 1) + (SHR(fallingBits, 24) AND 1) + (SHR(fallingBits, 25) AND 1) + (SHR(fallingBits, 26) AND 1) + (SHR(fallingBits, 27) AND 1) + (SHR(fallingBits, 28) AND 1) + (SHR(fallingBits, 29) AND 1) + (SHR(fallingBits, 30) AND 1) + (SHR(fallingBits, 31) AND 1);
noOfFallingBits := sumFalling;

prev_value := value;

END_FUNCTION_BLOCK