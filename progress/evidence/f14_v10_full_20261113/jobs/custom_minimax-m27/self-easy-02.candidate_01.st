FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel  : REAL;
    outletFlow : REAL;
    inletPermit : BOOL;
    resetBtn   : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun        : BOOL;
    alarmHigh      : BOOL;
    alarmLow       : BOOL;
    outletValveOpen : BOOL;
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;
    resetRising  : BOOL;
END_VAR
(* ENGINEERING_CONTRACT
 * =============================================================================
 * Alarm Latching Architecture (PUB003, PUB004, PUB007, PUB032-PUB040):
 *   - alarmHigh: SET on tankLevel >= 85.0 (PUB003), CLEAR on resetRising only
 *     when tankLevel < 85.0 (PUB032). Held until safe+reset.
 *   - alarmLow:  SET on tankLevel <= 15.0 (PUB003), CLEAR on resetRising only
 *     when tankLevel > 15.0 (PUB033). Held until safe+reset.
 *   - Simultaneous latching allowed; reset can clear only the already-safe one.
 *   - Rising-edge memory: prevResetBtn stores last-scan state; initial=FALSE.
 *   - Holding-across-level-change: resetRising = resetBtn AND NOT prevResetBtn
 *     requires release-and-repress for each new reset action.
 *   - Same-scan priority: danger condition sets alarm BEFORE reset logic;
 *     reset cannot clear a same-scan newly-set alarm (PUB042-PUB043).
 * Pump Interlock (PUB004, PUB005, PUB035, PUB036):
 *   - pumpRun = inletPermit AND NOT alarmHigh AND NOT alarmLow (PUB004).
 *   - Priority: alarmStop > inletPermit (PUB005 explicitly names alarm as stop
 *     authority; N10-S3 confirms any alarm blocks pump same-scan).
 *   - No other preconditions; outletFlow is observation-only.
 * Valve Command (PUB007, PUB037-PUB038):
 *   - outletValveOpen = NOT alarmLow (PUB007, N10-S4).
 *   - Valve closes when low alarm latched, opens otherwise (including reset
 *     scan with alarmLow=TRUE so valve stays closed per N10-S4 inverse).
 * Units/Boundaries:
 *   - High threshold: 85.0 (PUB003) - inclusive >=.
 *   - Low threshold:  15.0 (PUB003) - inclusive <=.
 *   - REAL comparisons for level; BOOL edge-detect for reset.
 * =============================================================================
 *)
    // Rising-edge detection for reset button
    resetRising := resetBtn AND NOT prevResetBtn;

    // High-level alarm: set immediately on danger, clear only via reset when safe
    // Same-scan: danger sets BEFORE reset check so new danger wins over new reset
    IF tankLevel >= 85.0 THEN
        alarmHigh := TRUE;
    ELSIF resetRising AND tankLevel < 85.0 THEN
        alarmHigh := FALSE;
    END_IF;

    // Low-level alarm: set immediately on danger, clear only via reset when safe
    IF tankLevel <= 15.0 THEN
        alarmLow := TRUE;
    ELSIF resetRising AND tankLevel > 15.0 THEN
        alarmLow := FALSE;
    END_IF;

    // Pump runs only when inlet permit granted AND both alarms are clear
    pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;

    // Outlet valve: open when low alarm is NOT latched
    outletValveOpen := NOT alarmLow;

    // Update previous scan state for next edge detection
    prevResetBtn := resetBtn;
END_FUNCTION_BLOCK

(* CONTRACT_RULES
[
  {"kind": "hold_until_reset", "output": "alarmHigh", "set_input": null, "reset_input": "resetBtn"},
  {"kind": "hold_until_reset", "output": "alarmLow",  "set_input": null, "reset_input": "resetBtn"}
]
*)