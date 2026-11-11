FUNCTION_BLOCK FB
VAR_INPUT
    THICKNESS_FAULT        : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN            : BOOL;
    FaultTimestamp         : DINT;
    CycleTime              : TIME;
END_VAR
VAR_OUTPUT
    THICKNESS_ALARM            : BOOL;
    Slab_Fault_Counter         : UINT;
    Slab_Runtime_Accumulator   : LINT;
    Slab_Fault_History         : ARRAY[0..4] OF DINT;
END_VAR
VAR
    FaultWindow    : ARRAY[0..24] OF BOOL;
    FaultRisingEdge : BOOL;
END_VAR

FaultRisingEdge := THICKNESS_FAULT AND NOT FaultWindow[0];

IF FaultRisingEdge AND THICKNESS_SIGNAL_VALID THEN
    Slab_Fault_Counter := Slab_Fault_Counter + 1;
    Slab_Fault_History[4] := Slab_Fault_History[3];
    Slab_Fault_History[3] := Slab_Fault_History[2];
    Slab_Fault_History[2] := Slab_Fault_History[1];
    Slab_Fault_History[1] := Slab_Fault_History[0];
    Slab_Fault_History[0] := FaultTimestamp;
END_IF

FaultWindow[24] := FaultWindow[23];
FaultWindow[23] := FaultWindow[22];
FaultWindow[22] := FaultWindow[21];
FaultWindow[21] := FaultWindow[20];
FaultWindow[20] := FaultWindow[19];
FaultWindow[19] := FaultWindow[18];
FaultWindow[18] := FaultWindow[17];
FaultWindow[17] := FaultWindow[16];
FaultWindow[16] := FaultWindow[15];
FaultWindow[15] := FaultWindow[14];
FaultWindow[14] := FaultWindow[13];
FaultWindow[13] := FaultWindow[12];
FaultWindow[12] := FaultWindow[11];
FaultWindow[11] := FaultWindow[10];
FaultWindow[10] := FaultWindow[9];
FaultWindow[9]  := FaultWindow[8];
FaultWindow[8]  := FaultWindow[7];
FaultWindow[7]  := FaultWindow[6];
FaultWindow[6]  := FaultWindow[5];
FaultWindow[5]  := FaultWindow[4];
FaultWindow[4]  := FaultWindow[3];
FaultWindow[3]  := FaultWindow[2];
FaultWindow[2]  := FaultWindow[1];
FaultWindow[1]  := FaultWindow[0];
FaultWindow[0]  := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID;

THICKNESS_ALARM := THICKNESS_SIGNAL_VALID AND (
    THICKNESS_FAULT OR
    FaultWindow[1]  OR FaultWindow[2]  OR FaultWindow[3]  OR FaultWindow[4]  OR
    FaultWindow[5]  OR FaultWindow[6]  OR FaultWindow[7]  OR FaultWindow[8]  OR
    FaultWindow[9]  OR FaultWindow[10] OR FaultWindow[11] OR FaultWindow[12] OR
    FaultWindow[13] OR FaultWindow[14] OR FaultWindow[15] OR FaultWindow[16] OR
    FaultWindow[17] OR FaultWindow[18] OR FaultWindow[19] OR FaultWindow[20] OR
    FaultWindow[21] OR FaultWindow[22] OR FaultWindow[23] OR FaultWindow[24]
);

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    FaultWindow[0]  := FALSE;
    FaultWindow[1]  := FALSE;
    FaultWindow[2]  := FALSE;
    FaultWindow[3]  := FALSE;
    FaultWindow[4]  := FALSE;
    FaultWindow[5]  := FALSE;
    FaultWindow[6]  := FALSE;
    FaultWindow[7]  := FALSE;
    FaultWindow[8]  := FALSE;
    FaultWindow[9]  := FALSE;
    FaultWindow[10] := FALSE;
    FaultWindow[11] := FALSE;
    FaultWindow[12] := FALSE;
    FaultWindow[13] := FALSE;
    FaultWindow[14] := FALSE;
    FaultWindow[15] := FALSE;
    FaultWindow[16] := FALSE;
    FaultWindow[17] := FALSE;
    FaultWindow[18] := FALSE;
    FaultWindow[19] := FALSE;
    FaultWindow[20] := FALSE;
    FaultWindow[21] := FALSE;
    FaultWindow[22] := FALSE;
    FaultWindow[23] := FALSE;
    FaultWindow[24] := FALSE;
END_IF

IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + 1;
END_IF
END_FUNCTION_BLOCK