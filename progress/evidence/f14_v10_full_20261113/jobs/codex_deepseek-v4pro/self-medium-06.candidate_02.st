FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT
 * power: zero branch has same-scan priority for !enable/fault/reset_rise; valid branch = LIMIT(0.0, bias + correction, 100.0).
 * correction: valid branch = nine-rule weighted centroid, x=e/10.0 and y=de/2.0 both limited to [-1,1]; result is not clamped.
 * fault: combinational = NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0.
 * history: ePrev and history flag cleared on !enable, fault, or reset rise; first valid scan after clear uses de=0.
 * ePrev updates only on valid scans; holding resetBtn does not hold outputs zero after the rising-scan.
 * units: setpoint/temperature degC, scanSeconds s, bias/power/correction %, de degC/s.
 *)

(* CONTRACT_RULES [] *)
VAR_INPUT
    enable : BOOL;
    resetBtn : BOOL;
    sensorValid : BOOL;
    setpoint : REAL;
    temperature : REAL;
    scanSeconds : REAL;
    bias : REAL;
END_VAR
VAR_OUTPUT
    power : REAL;
    correction : REAL;
    fault : BOOL;
END_VAR
VAR
    tmp_prev_reset_btn : BOOL := FALSE;
    tmp_history_valid : BOOL := FALSE;
    tmp_e_prev : REAL := 0.0;
    tmp_reset_rising : BOOL;
    tmp_e : REAL;
    tmp_de : REAL;
    tmp_x : REAL;
    tmp_y : REAL;
    tmp_mu_e_n : REAL;
    tmp_mu_e_z : REAL;
    tmp_mu_e_p : REAL;
    tmp_mu_de_n : REAL;
    tmp_mu_de_z : REAL;
    tmp_mu_de_p : REAL;
    tmp_w_nn : REAL;
    tmp_w_nz : REAL;
    tmp_w_np : REAL;
    tmp_w_zn : REAL;
    tmp_w_zz : REAL;
    tmp_w_zp : REAL;
    tmp_w_pn : REAL;
    tmp_w_pz : REAL;
    tmp_w_pp : REAL;
    tmp_weight_sum : REAL;
    tmp_weighted_output : REAL;
END_VAR

tmp_reset_rising := resetBtn AND (NOT tmp_prev_reset_btn);
fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF (NOT enable) OR fault OR tmp_reset_rising THEN
    power := 0.0;
    correction := 0.0;
    tmp_history_valid := FALSE;
    tmp_e_prev := 0.0;
ELSE
    tmp_e := setpoint - temperature;

    IF tmp_history_valid THEN
        tmp_de := (tmp_e - tmp_e_prev) / scanSeconds;
    ELSE
        tmp_de := 0.0;
    END_IF;

    tmp_x := LIMIT(-1.0, tmp_e / 10.0, 1.0);
    tmp_y := LIMIT(-1.0, tmp_de / 2.0, 1.0);

    tmp_mu_e_n := MAX(-tmp_x, 0.0);
    tmp_mu_e_z := 1.0 - ABS(tmp_x);
    tmp_mu_e_p := MAX(tmp_x, 0.0);

    tmp_mu_de_n := MAX(-tmp_y, 0.0);
    tmp_mu_de_z := 1.0 - ABS(tmp_y);
    tmp_mu_de_p := MAX(tmp_y, 0.0);

    tmp_w_nn := tmp_mu_e_n * tmp_mu_de_n;
    tmp_w_nz := tmp_mu_e_n * tmp_mu_de_z;
    tmp_w_np := tmp_mu_e_n * tmp_mu_de_p;
    tmp_w_zn := tmp_mu_e_z * tmp_mu_de_n;
    tmp_w_zz := tmp_mu_e_z * tmp_mu_de_z;
    tmp_w_zp := tmp_mu_e_z * tmp_mu_de_p;
    tmp_w_pn := tmp_mu_e_p * tmp_mu_de_n;
    tmp_w_pz := tmp_mu_e_p * tmp_mu_de_z;
    tmp_w_pp := tmp_mu_e_p * tmp_mu_de_p;

    tmp_weight_sum := tmp_w_nn + tmp_w_nz + tmp_w_np
                    + tmp_w_zn + tmp_w_zz + tmp_w_zp
                    + tmp_w_pn + tmp_w_pz + tmp_w_pp;

    tmp_weighted_output := tmp_w_nn * (-30.0)
                         + tmp_w_nz * (-20.0)
                         + tmp_w_np * (-10.0)
                         + tmp_w_zn * (-10.0)
                         + tmp_w_zz * 0.0
                         + tmp_w_zp * 10.0
                         + tmp_w_pn * 10.0
                         + tmp_w_pz * 20.0
                         + tmp_w_pp * 30.0;

    IF tmp_weight_sum <= 0.0 THEN
        correction := 0.0;
    ELSE
        correction := tmp_weighted_output / tmp_weight_sum;
    END_IF;

    power := LIMIT(0.0, bias + correction, 100.0);

    tmp_e_prev := tmp_e;
    tmp_history_valid := TRUE;
END_IF;

tmp_prev_reset_btn := resetBtn;

END_FUNCTION_BLOCK