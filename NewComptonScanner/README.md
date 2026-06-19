# Compton Scanner — TMCM-3351 Motor Controller Scripts

Hardware: TMCM-3351 3-axis closed-loop stepper motor controller.
Three sleds move vertically. Positive encoder direction = downward, negative = upward.

* * *

## Repository files

**Loop mode — Julia-driven (active workflow)**

| File | Type | Purpose |
|------|------|---------|
| `TMCMCode_newversion.tmc` | TMCL firmware | Persistent state machine running on the board. Loaded once via TMCL-IDE; auto-starts on every power-on. Controlled by Julia via GP 10. |
| `tmcl_control_layer.jl` | Julia module | Full API wrapping every board command as a named Julia function. Included by all scripts below. |
| `ScanSequence.jl` | Julia script | Normal session: startup → calibration → move. Use after a clean power-off or at the start of a measurement day. |
| `AfterRedButton_CodeLooping.jl` | Julia script | Resume after a red-button press/unpress **with USB still connected**. Calibration and encoder positions survive in RAM; only `startup!` is required. |
| `After_UnplugBoard.jl` | Julia script | Full recovery after complete power loss (board unplugged, or red button pressed with USB also disconnected). Must reload TMCL code, call `RefZero` (via RefZero_run_only_once_after_unplugging_board!(dev)) once, then calibrate. |
| `DisableAutostart.tmc` | TMCL snippet | One-shot utility to disable auto-start of `TMCMCode_newversion.tmc` on power-on (`SGP 77,0,0`). Load and execute once via TMCL-IDE; the board then powers on idle until a program is explicitly started. |

**Creator Mode — manual TMCL-IDE workflow (legacy)**

| File | Type | Purpose |
|------|------|---------|
| `FullTest_CreatorMode.tmc` | TMCL script | Self-contained script for TMCL-IDE Creator Mode. No Julia required. Uncomment the step you want and execute. Used for initial hardware bring-up and hard-stop reproducibility tests. |

* * *

## Main script: FullTest_CreatorMode.tmc

Single self-contained TMCL script with all routines. Open in TMCL-IDE Creator Mode,
uncomment the steps you want to run, and execute.

### Routine execution order

**Step 1 — always run first at startup**
```
CSUB PowerOn
CSUB StartInit
CSUB DisableClosedLoop
CSUB EnableClosedLoop
CSUB ReferenceZero
```
Sets motion parameters, PID/regulator values, enables closed loop, and sets the
current sled positions as coordinate origin (encoder = 0).

**Step 2 — calibrate to calibration blocks**

Two options are available:

*Option A — one axis at a time (`StartCalibration2`):*
Uncomment only the axis block you want to calibrate. Each axis must be done
independently — user variables in bank 2 persist per axis. Make sure all 3 axes
have been calibrated before running StartMove2.

*Option B — all 3 axes simultaneously (`StartCalibrationSimultaneousAxis`):*
```
CSUB StartCalibrationSimultaneousAxis
```
Starts all 3 axes at once, polls them in a round-robin loop, and saves each
axis's encoder position the instant it stalls against its block. MST is issued
per axis immediately on stall — no axis is held against its block waiting for
the others. Use this option when all 3 blocks are in position and the sleds
start physically above the blocks.

**Step 3 — move upward and hard stop**
```
CSUB StartMove2
```
Moves all axes 500,000 encoder counts above their saved copper block positions.
To change the target height, modify the `CALC SUB,500000` value in `StartMove2`.
The same routine can be re-run with a different offset to move up or down from
the current position.

**Step 4 — measurement mode (optional)**
```
CSUB EnterMeasurementMode
// perform HPGe measurement
CSUB ExitMeasurementMode
```
`EnterMeasurementMode` de-energizes motors for low-noise HPGe detector data acquisition.
For the full sequence and observed encoder drift, see [Measurement mode](#measurement-mode----entermeasurementmode--exitmeasurementmode) below — the `TMCMCode_newversion.tmc` implementation is the current reference.

`ExitMeasurementMode` restores the motion system after measurement. Re-syncs both the
ramp generator (AP 1) and CL target (AP 0) to the current encoder position before
restoring currents, to prevent oscillation if the sled drifted during measurement.


**Step 5 — power off**
```
CSUB PowerOff
```

* * *

### What MST does and why it matters

`MST x` issues an immediate motor stop command. In closed-loop mode, after the motor
stalls against the copper block, the CL controller has been fighting at maximum current
with its integrator wound up. `MST` stops the commanded motion but does NOT reset the
chip internal state (commutation angle tracking, integrator).

### Why ReferenceZero works at startup but not after calibration

`ReferenceZero` resets encoder position (SAP 209 = 0), then syncs actual position
(AAP 1) and target position (AAP 0) to match. At startup this is safe: the CL
controller is in a clean state, no prior stall, all registers are consistent.

After copper block calibration, the internal state has diverged from
what a clean power-on provides. Calling `ReferenceZero` at this point resets the
TMCL-visible registers (SAP 209, AAP 1, AAP 0) but NOT the chip's internal state.
The CL controller then has a mismatch between its internal commutation state and
the new encoder=0 reference, which causes it to behave incorrectly during StartMove.

Re-running the full init sequence (PowerOn → StartInit → DisableCL → EnableCL →
ReferenceZero) after calibration does NOT fix this: PowerOn already contains the
same position sync as ReferenceZero, so the same corruption occurs.

### The fix: save encoder positions, never reset reference after calibration

`StartCalibration2` saves `GAP 209` (encoder position) for each axis at the moment
the sled stalls on the copper block, storing it in user variable bank 2 (indices 0/1/2).
`StartMove2` reads these saved positions and computes absolute targets
(`copper_block_pos - 500000`) via `GGP / CALC SUB / ACO`, then calls `MVP COORD`.

This means:
- No `ReferenceZero` is ever called after calibration
- The CL controller's internal state is undisturbed from when the motor stopped
- Hard stop detection works correctly

### User variable map (bank 2, accessed via AGP/GGP)

| Index | Name            | Contents                                                      |
|-------|-----------------|---------------------------------------------------------------|
| 0     | CALIB_POS_AXIS0 | Encoder position at calibration block, axis 0                 |
| 1     | CALIB_POS_AXIS1 | Encoder position at calibration block, axis 1                 |
| 2     | CALIB_POS_AXIS2 | Encoder position at calibration block, axis 2                 |
| 3     | axis0Done       | Temporary done flag used by `StartCalibrationSimultaneousAxis` (0/1, cleared on exit) |
| 4     | axis1Done       | Temporary done flag used by `StartCalibrationSimultaneousAxis` (0/1, cleared on exit) |
| 5     | axis2Done       | Temporary done flag used by `StartCalibrationSimultaneousAxis` (0/1, cleared on exit) |

User variables persist as long as the board is powered. Calibrating one axis does
not overwrite the others. Indices 3/4/5 are only meaningful during execution of
`StartCalibrationSimultaneousAxis` and are used internally to track which axes have
already stalled and been saved. Both `StartCalibration2` and
`StartCalibrationSimultaneousAxis` write to the same indices 0/1/2, so `StartMove2`
works unchanged after either calibration routine.

* * *

## Hard stop reproducibility measurements

Scale: 1 motor turn = 5 mm = 51,200 microsteps → 1 ustep ≈ 0.0000977 mm

### 1st hard stop — SAP 17 = 51,200 pps² (initial value, not yet changed)

| Sled |Block initialpos (encoder) | Target   |Encoder after 1st hard stop | Steps moved |
|------|---------------------------|----------|----------------------------|-------------|
| 0    | 501,017                   | −500,000 | 345,395                    | 155,622     |
| 1    | 498,790                   | −500,000 | 343,168                    | 155,622     |
| 2    | 499,020                   | −500,000 | 346,086                    | 152,934     |

sleds deviation after hard stop: 155,622 − 152,934 = **2,688 usteps = 0.26 mm**

`EmergencyStop2` raises SAP 17 to 1,000,000 during hard stop. `RecoverDeceleration` then restores it to 51,200.

* * *

### 2nd hard stop — comparing two SAP 17 strategies


| Sled | Target   | Encoder after 2nd hard stop | Steps moved from copper block |
|------|----------|-----------------------------|-------------------------------|
| 0    | −500,000 | 241,971                     | 259,046                       |
| 1    | −500,000 | 239,795                     | 258,995                       |
| 2    | −500,000 | 245,376                     | 253,644                       |

sleds deviation after hard stop: 259,046 − 253,644 = **5,402 usteps = 0.52 mm**

**Finish the move (the 500,000 steps) after the 2 hard stops**

| Sled | Final encoder pos | Steps moved from copper block |
|------|-------------------|-------------------------------|
| 0    | 1,075             | 499,942                       |
| 1    | −1,127            | 499,917                       |
| 2    | −666              | 499,686                       |

sleds deviation after the 2 hard stops and finishing the move: 499,942 − 499,686 = **256 usteps = 0.025 mm**

* * *

## Deprecated: StartCalibration + StartMove instead use StartCalibration2 + StartMove2

`StartCalibration` moves each axis to the copper block and stops. After this, the
only valid next step is `StartMove` immediately — no `ReferenceZero`, no
`DisableCL/EnableCL` in between. `StartMove` uses hardcoded target `SCO 0,x,-500000`,
which is only meaningful if `ReferenceZero` was called at startup (so -500,000 is
500,000 counts above origin, not above the copper block).

If `ReferenceZero` or `DisableCL/EnableCL` is called after `StartCalibration`,
hard stop detection breaks. Recovery requires a full board power-cycle and rerunning
Step 1 from scratch.

This approach is kept in the script for reference but `StartCalibration2 + StartMove2`
should be used instead.


* * *

## Other scripts (legacy, single-step use)

| Script                              | Purpose                                      |
|-------------------------------------|----------------------------------------------|
| 1step_CreatorMode_3axisMove.tmc     | Set up closed loop and initial variables     |
| 2step_actualspeed_CreatorMode_3axisMove.tmc | Speed monitoring variant               |
| CalibrationMode_HitPlatform.tmc     | Calibrate by hitting bottom platform         |
| CalibrationMode_MetalBlock.tmc      | Calibrate by hitting metal block             |
| TMCM_FullCreatorMode.tmc            | Awaiting Julia inputs (not tested)           |

# TMCMCode_newversion.tmc — Julia-driven state machine

This script implements the same physical behaviour as `FullTest_CreatorMode.tmc` but
runs as a **persistent loop** on the TMCM board, controlled by Julia via the TMCL
global parameter bank 2.  Instead of uncommenting routines in Creator Mode, Julia
writes a command number to **GP 10 (bank 2)** and reads it back as 0 when the task
is done.  The program auto-starts after every power-on (SGP 77, Bank 0 = 1 stored in
EEPROM).

## Important: red button and power-on behaviour

The program is stored in **flash (non-volatile)**. It auto-starts on **every power-on** — including after a red-button press/release and after a complete power cycle (USB + power disconnected) — regardless of whether the program was previously stopped with `end_program(dev)`.

**Consequences:**
- Pressing and releasing the red button (with USB connected and board powered) always restarts the last uploaded program.
- A complete power-off followed by power-on also restarts the last uploaded program.
- `end_program(dev)` only stops the software loop; it does not prevent the program from restarting on any subsequent power-on or red-button press.
- The program stored in flash persists until a new one is uploaded via TMCL-IDE.

**In practice:** after calling `end_program(dev)`, do not press the red button or power-cycle the board if you want the program to stay stopped.

**Auto-start:** the firmware has auto-start enabled (`SGP 77, 0, 1`). This means there is no way to have a program-free board after a red-button press or power cycle as long as auto-start remains enabled. Disabling it (`SGP 77, 0, 0`) would require manually starting the program from TMCL-IDE at the beginning of every session.

**To get a program-free board:** load `DisableAutostart.tmc` via TMCL-IDE. It stops all motors, disables closed-loop, zeros all currents, disables auto-start, and halts. Safe to load in any state — whether the motors are running, stuck, or already at rest. After it runs, pressing the red button or power-cycling the board will not restart any program. To restore normal operation, reload `TMCMCode_newversion.tmc` via TMCL-IDE (re-enable auto-start in the upload settings).

**Verified test — DisableAutostart.tmc:**

Starting state: TMCMCode_newversion.tmc running (after red-button press/unpress), `is_program_running` = true. Sleds at ~2 cm above calibration block: calib = (410,368 · 410,033 · 410,881), encoder = (204,554 · 204,042 · 206,362). CL DISABLED (safety init ran), currents = 0.

1. Load `DisableAutostart.tmc` via TMCL-IDE → `is_program_running` = **false** (STOP executed immediately).
2. Press red button → unpress red button.
3. Re-connect Julia → `is_program_running` = **false** ✓ — no program auto-started.
   Board state: encoder = (204,554 · 204,042 · 205,952), CL DISABLED, currents = 0. Axis 2 encoder drifted 410 usteps (0.040 mm) during the de-energization window — axes 0 and 1 unchanged.
4. Load `TMCMCode_newversion.tmc` via TMCL-IDE → `is_program_running` = **true** ✓ — normal operation restored, auto-start re-enabled.
   Encoder positions preserved: (204,554 · 204,042 · 205,952). CL DISABLED (safety init), currents = 0 — `startup!` required before any move.



### Architecture

```
Julia                           Board (TMCMCode_newversion.tmc)
─────                           ──────────────────────────────
SGP 10, 2, N  ────────────────▶  GGP TMCM_Command, 2
                                  COMP N  →  dispatch to routine
                                  routine executes
                                  SGP 10, 2, 0
GGP 10 == 0   ◀─────────────────  (idle, ready for next command)
```

### Safety init on every program start

On every program start — including after a red-button press/unpress — the firmware
immediately executes before entering the main loop:

```tmcl
SAP 129, 0, 0   // disable closed-loop axis 0
SAP 129, 1, 0   // disable closed-loop axis 1
SAP 129, 2, 0   // disable closed-loop axis 2
SAP 6, 0, 0     // zero run current axis 0  (and 1, 2)
SAP 7, 0, 0     // zero standby current axis 0  (and 1, 2)
```

This guarantees all axes are de-energized and CL is disabled whenever the board
restarts.  The self-locking lead-screw spindles hold the sled positions without
motor current.  Julia's `startup!` re-applies currents and re-enables CL.

* * *

## State machine command register (GP 10, bank 2)

Julia writes one of these values to GP 10 to trigger a routine.  The board sets
GP 10 back to 0 when the routine completes.  Julia must wait for GP 10 = 0 before
sending the next command (use `wait_for_idle(dev)`).

| GP 10 | Routine name | Julia function | Notes |
|-------|-------------|---------------|-------|
| 0 | Idle | — | Board is ready for the next command |
| 1 | PowerOn | `power_on(dev)` | Write motion params (GP 4/5/6/7/17/210) to all axes via AAP; sync encoder→actual→target |
| 2 | StartInit | `start_init(dev)` | Write all closed-loop PID params (GP 108–126/212/213) to all axes via AAP |
| 3 | DisableClosedLoop | `disable_closed_loop(dev)` | SAP 129,x,0; polls AP 133 until confirmed disabled on all 3 axes |
| 4 | EnableClosedLoop | `enable_closed_loop(dev)` | SAP 129,x,1; polls AP 133 until confirmed enabled on all 3 axes |
| 5 | ReferenceZero | `reference_zero(dev)` | SAP 209,x,0 — zero encoder at current position; sync actual and target. **Only once after unplugging** |
| 6 | CalibrateAxis0 | `calibrate_axis(dev, 0)` | Descend axis 0 to block; MST on stall; save encoder pos → GP 53 |
| 7 | CalibrateAxis1 | `calibrate_axis(dev, 1)` | Descend axis 1 to block; MST on stall; save encoder pos → GP 54 |
| 8 | CalibrateAxis2 | `calibrate_axis(dev, 2)` | Descend axis 2 to block; MST on stall; save encoder pos → GP 55 |
| 9 | StartMove | `move_all_axes_to(dev, nsteps, speed)` | Move all 3 axes to `nsteps` microsteps **above the calibration block** (Julia reads GP 53/54/55, computes `calib_pos − nsteps`, writes absolute targets to GP 59/60/61). Hard stop on any axis stops all three — see [Hard stop detection](#hard-stop-detection-in-startmove) |
| 10 | PowerOff | `power_off(dev)` | MST all axes; disable CL; zero run and standby currents |
| 11 | EnterMeasurementMode | `enter_measurement_mode(dev)` | MST all axes; sync target to encoder; zero currents — eliminates motor EMI |
| 12 | ExitMeasurementMode | `exit_measurement_mode(dev)` | Re-sync target to encoder; restore currents (run=25, standby=8) |
| 13 | MoveAxis0 | `move_absolute_axis_to(dev, 0, pos, speed)` | Move axis 0 to `pos` microsteps (absolute encoder position). Hard stop detection: if velocity reaches 0 before position is reached, syncs CL target and ramp to actual position and returns (GP10=0). |
| 14 | MoveAxis1 | `move_absolute_axis_to(dev, 1, pos, speed)` | Move axis 1 to `pos` microsteps (absolute encoder position). Same hard stop detection as MoveAxis0. |
| 15 | MoveAxis2 | `move_absolute_axis_to(dev, 2, pos, speed)` | Move axis 2 to `pos` microsteps (absolute encoder position). Same hard stop detection as MoveAxis0. |
| 16 | SimultaneousCalibration | `calibrate!(dev)` | All 3 axes descend together in a round-robin poll loop; each is MST'd and saved independently on stall; GP10=0 when all 3 done |
| 17 | MoveAxis0AboveCalib | `move_axis_above_calib(dev, 0, nsteps, speed)` | Move axis 0 to `nsteps` above its calibration block; Julia writes absolute target to GP 59 |
| 18 | MoveAxis1AboveCalib | `move_axis_above_calib(dev, 1, nsteps, speed)` | Move axis 1 to `nsteps` above its calibration block; Julia writes absolute target to GP 60 |
| 19 | MoveAxis2AboveCalib | `move_axis_above_calib(dev, 2, nsteps, speed)` | Move axis 2 to `nsteps` above its calibration block; Julia writes absolute target to GP 61 |
| 99 | Error / EmergencyStop | — | Set by board on hard stop; waits for next Julia command |
| 100 | Ping | `is_program_running(dev)` | No-op; board clears GP10 to 0. Used by Julia to detect whether the TMCL program is running — no movement, no state change |
| 999 | EndLoop | `end_program(dev)` | MST all axes; STOP — terminates the TMCL program |

* * *
### High-level composite functions

| Function | Sequence | Notes |
|----------|---------|-------|
| `startup!(dev)` | `power_on` → `start_init` → `disable_closed_loop` → `enable_closed_loop` | Once per power-cycle, before calibration. Sleds must be physically above the calibration blocks. |
| `calibrate!(dev)` | `calibrate_simultaneous` → STGP 53/54/55 to EEPROM | Can be re-run as many times as needed within a session. |
| `move_all_axes_to(dev, nsteps, speed)` | reads GP 53/54/55 → writes GP 59/60/61 → cmd 9 | Move axes 0, 1 and 2 simultaneously to `nsteps` microsteps above their respective calibration blocks. Hard stop on any axis stops all three (see below). |
| `move_all_axes_to_cm(dev, dist_cm, speed_cm_s)` | converts to usteps → `move_all_axes_to` | Same as above (axes 0, 1 and 2) with distance in cm and speed in cm/s. Conversion: 102,400 usteps/cm (5 mm/rev = 0.5 cm/rev, 51,200 usteps/rev). |
| `move_axis_above_calib(dev, ax, nsteps, speed)` | reads GP 53+ax → writes GP 59+ax → cmd 17/18/19 | Move a single axis (`ax` = 0, 1 or 2) to `nsteps` microsteps above its calibration block. The other two axes are not moved. Requires a prior `calibrate!`. |
| `move_axis_above_calib_cm(dev, ax, dist_cm, speed_cm_s)` | converts to usteps → `move_axis_above_calib` | Same as above (single axis, `ax` = 0, 1 or 2) with distance in cm and speed in cm/s. |
| `move_absolute_axis_to(dev, ax, pos, speed)` | writes GP 0 → cmd 13/14/15 | Move a single axis (`ax` = 0, 1 or 2) to an absolute encoder position (microsteps). The other two axes are not moved. |
| `end_measurement!(dev)` | SAP current restore → `exit_measurement_mode` | Restore currents via SAP (more reliable than AAP/GGP with CL active). |
| `shutdown!(dev)` | `power_off` | Clean pre-power-off: MST, disable CL, zero currents. |
| `RefZero_run_only_once_after_unplugging_board!(dev)` | `reference_zero` | **Only after full power loss** (board unplugged, or red button pressed with USB also disconnected) — zeros encoder at current sled positions. Not needed after a red-button press/unpress with USB still connected, because the encoder positions survive in MCU RAM. |

### Diagnostic functions

| Function | Returns | Description |
|----------|---------|-------------|
| `read_axis_status(dev)` | `(calib_pos, encoder_pos)` | Logs GP 53/54/55 (calibration block positions) and AP 209 (current encoder positions) for all 3 axes. After a successful `calibrate!`, these two sets of values should be identical. |
| `read_closed_loop_status(dev)` | `(axis0, axis1, axis2)` Booleans | Logs ENABLED/DISABLED for each axis (AP 129). |
| `board_status(dev)` | named tuple | Logs supply voltage [V], temperature [°C/K], run/standby current (AP, axis 0), and all motion parameters from GP Bank 2: max speed, acceleration, deceleration, current, standby current, encoder resolution. |
| `is_program_running(dev)` | `Bool` | Sends Ping (cmd 100), waits 100 ms, checks if GP 10 was cleared to 0. Returns `true` if the TMCL program is running. No movement, no state change. |

## GP Bank 2 data registers

Julia writes these **before** sending the relevant command.

**Memory types and what survives each power event:**

**Hardware note — two separate power domains:**

The TMCM-3351 has two independent power supplies:

- **Motor supply** — the high-voltage/high-current rail that drives the motor coils
  and encoder interfaces.  The red button cuts this rail.
- **Logic supply** — the MCU, RAM, and USB interface.  When the board is connected
  to a PC via USB, the bus provides ~0.5 V which is enough to keep the MCU alive even
  when the motor supply is cut.

This means a red-button press/unpress is **not a full power-off** — it is a
partial-power state where the MCU and its RAM remain live while the motion hardware
is dead.  A full unplug (or powering off the PC-side USB) is the only event that
actually clears the MCU RAM.

The small encoder drift observed after a red-button press (~250 usteps, ≈ 0.025 mm) comes from
the closed-loop disable/enable cycle: the safety init disables CL and zeros currents,
then `startup!` disables and re-enables CL again.  Each time CL is disabled the motor
is no longer actively held at its target position and the sled can move slightly under
gravity or mechanical play before CL is restored.

**Consequence: unplugging USB after the red button is equivalent to a full unplug.**
If the USB cable is disconnected while the motor supply is also off (i.e. after
pressing the red button), the logic supply drops, the MCU RAM is cleared, and all
AP values — including encoder positions — are lost.  This scenario is identical to
unplugging everything: the TMCL program must be reloaded, `RefZero` must be called
once to re-establish the encoder zero, and a full calibration is required.  The only
thing that would still survive is the EEPROM-backed calibration positions (GP 53/54/55
saved by `calibrate!`), but without a valid encoder zero reference those positions
are meaningless until `RefZero` (via `RefZero_run_only_once_after_unplugging_board!(dev)`) is run again.

The TMCM-3351 has two distinct memory spaces with different survival rules:

- **Global Parameters (GP, Bank 2) — board RAM**, readable/writable via GGP/SGP.
  Indices 0–55 *can* be saved to EEPROM with the STGP opcode, but they are not
  saved automatically.  `calibrate!` explicitly calls STGP on GP 53/54/55 so the
  calibration block positions survive a full power cut.  All other GP values (motion
  params, PID params, move targets) are not STGP'd and are rewritten by Julia at the
  start of every session via `startup!`.

- **Axis Parameters (AP) — axis-local RAM**, readable/writable via GAP/SAP.  AP values
  like closed-loop enable (AP 129), run/standby current (AP 6/7), and encoder position
  (AP 209) **survive a red-button press/unpress** because the MCU RAM never loses
  power (USB keeps the logic supply alive).  They are lost only on a full unplug.

**Why closed-loop is DISABLED after a red-button press/unpress** despite AP values
surviving in RAM:

The red button restarts the TMCL program from the beginning.  The safety-init block
at the top of `TMCMCode_newversion.tmc` runs unconditionally before the main loop and
explicitly overwrites those AP values:

```tmcl
SAP 129, 0, 0   // disable closed-loop axis 0  (overwrites whatever was in AP 129)
SAP 6,   0, 0   // zero run current axis 0
SAP 7,   0, 0   // zero standby current axis 0
```

CL is disabled not because the AP value was lost, but because the firmware
deliberately forces it off for safety on every restart.  Encoder positions (AP 209)
are intentionally left untouched by the safety init — they persist with negligible
mechanical drift (0 to ~500 usteps, ≤ 0.05 mm) while the motors were de-energized.

| Value | Red button press/unpress | Full unplug |
|-------|--------------------------|-------------|
| Calibration positions GP 53/54/55 | **Yes** — GP Bank 2 RAM + EEPROM backup | **Yes** — EEPROM backup by `calibrate!` |
| Encoder positions AP 209 | **Yes** — AP RAM survives; small drift expected | **No** — RAM cleared; random on boot |
| Closed-loop enable AP 129 | AP survives but **firmware safety init disables it** | No — RAM cleared, safety init disables it |
| Run/standby current AP 6/7 | AP survives but **firmware safety init zeros them** | No — RAM cleared, safety init zeros them |
| CL PID params AP 108–126 | **Yes** — AP RAM survives; `startup!` rewrites anyway | No — RAM cleared; `startup!` required |
| TMCL program code | **Yes** — EEPROM; auto-starts on power-on unless `DisableAutostart.tmc` was loaded | **Yes** — EEPROM; same auto-start behaviour |

This is why the startup sequence after a red button is shorter than after unplugging:

* Red button: `startup!`, `calibrate!` (if wanted) and move.

* Full unplug (red button + usb disconnected): `startup!`, `RefZero_run_only_once_after_unplugging_board!(dev)`, `calibrate!` and move.
positions survive a full power cut.

| GP index | Julia constant | Written by | Read by |
|----------|---------------|-----------|--------|
| 0 | `GP_TARGET_POS` | Julia | MoveAxis0/1/2 (absolute encoder target) |
| 4 | `GP_MAX_SPEED` | Julia | PowerOn, StartMove, MoveAxis0/1/2, SimultaneousCalibration |
| 5 | `GP_MAX_ACCELERATION` | Julia | PowerOn |
| 6 | `GP_MAX_CURRENT` | Julia | PowerOn |
| 7 | `GP_STANDBY_CURRENT` | Julia | PowerOn |
| 10 | `GP_TMCM_COMMAND` | Julia (trigger) / board (clear to 0) | Main dispatch loop |
| 17 | `GP_MAX_DECELERATION` | Julia | PowerOn |
| 53 | `GP_CALIB_POS_AXIS0` | Board (calibration routines); EEPROM-backed | StartMove, `move_all_axes_to` |
| 54 | `GP_CALIB_POS_AXIS1` | Board (calibration routines); EEPROM-backed | StartMove, `move_all_axes_to` |
| 55 | `GP_CALIB_POS_AXIS2` | Board (calibration routines); EEPROM-backed | StartMove, `move_all_axes_to` |
| 56 | `GP_CALIB_DONE_AXIS0` | Board (internal) | SimultaneousCalibration done flag; cleared on exit |
| 57 | `GP_CALIB_DONE_AXIS1` | Board (internal) | SimultaneousCalibration done flag; cleared on exit |
| 58 | `GP_CALIB_DONE_AXIS2` | Board (internal) | SimultaneousCalibration done flag; cleared on exit |
| 59 | `GP_MOVE_TARGET_AXIS0` | Julia | StartMove (cmd 9) and MoveAxis0AboveCalib (cmd 17); absolute target = `calib_pos − nsteps` |
| 60 | `GP_MOVE_TARGET_AXIS1` | Julia | StartMove (cmd 9) and MoveAxis1AboveCalib (cmd 18); absolute target = `calib_pos − nsteps` |
| 61 | `GP_MOVE_TARGET_AXIS2` | Julia | StartMove (cmd 9) and MoveAxis2AboveCalib (cmd 19); absolute target = `calib_pos − nsteps` |
| 108 | `GP_CL_GAMMA_VMIN` | Julia | StartInit |
| 109 | `GP_CL_GAMMA_VMAX` | Julia | StartInit |
| 110 | `GP_CL_MAXGAMMA` | Julia | StartInit |
| 111 | `GP_CL_BETA` | Julia | StartInit |
| 113 | `GP_CL_CURRENTMIN` | Julia | StartInit |
| 114 | `GP_CL_CURRENTMAX` | Julia | StartInit |
| 115 | `GP_CL_CORRECTION_VELOCITY_P` | Julia | StartInit |
| 116 | `GP_CL_CORRECTION_VELOCITY_I` | Julia | StartInit |
| 117 | `GP_CL_CORRECTION_VELOCITY_I_CLIP` | Julia | StartInit |
| 118 | `GP_CL_CORRECTION_VELOCITY_DV_CLK` | Julia | StartInit |
| 119 | `GP_CL_CORRECTION_VELOCITY_DV_CLIP` | Julia | StartInit |
| 120 | `GP_CL_UPSCALE_DELAY` | Julia | StartInit |
| 121 | `GP_CL_DOWNSCALE_DELAY` | Julia | StartInit |
| 124 | `GP_CL_CORRECTION_POS` | Julia | StartInit |
| 125 | `GP_CL_MAX_CORRECTION_TOLERANCE` | Julia | StartInit |
| 126 | `GP_CL_STARTUP` | Julia | StartInit |
| 134 | `GP_POS_WINDOW` | Julia | StartInit |
| 210 | `GP_ENCODER_RESOLUTION` | Julia | PowerOn |
| 212 | `GP_MAX_ENCODER_DEVIATION` | Julia | StartInit |
| 213 | `GP_MAX_VELOCITY_DEVIATION` | Julia | StartInit |

* * *

## Behaviour equivalence with FullTest_CreatorMode.tmc

Both scripts implement identical physical routines.  The difference is the driving
mechanism: FullTest requires manual uncomment/run in Creator Mode per step;
TMCMCode_newversion runs autonomously and accepts commands over the GP register
interface.
| `FullTest_CreatorMode.tmc` CSUB | Julia function | GP 10 |
|----------------------------------|---------------|-------|
| `CSUB PowerOn` | `power_on(dev)` | 1 |
| `CSUB StartInit` | `start_init(dev)` | 2 |
| `CSUB DisableClosedLoop` | `disable_closed_loop(dev)` | 3 |
| `CSUB EnableClosedLoop` | `enable_closed_loop(dev)` | 4 |
| `CSUB ReferenceZero` | `reference_zero(dev)` | 5 |
| `CSUB StartCalibrationSimultaneousAxis` | `calibrate_simultaneous(dev)` | 16 |
| `CSUB StartMove2` (−500,000) | `move_all_axes_to(dev, 500_000, 51_200)` | 9 |
| *(no equivalent — per-axis)* | `move_axis_above_calib(dev, 0, nsteps, speed)` | 17 |
| *(no equivalent — per-axis)* | `move_axis_above_calib(dev, 1, nsteps, speed)` | 18 |
| *(no equivalent — per-axis)* | `move_axis_above_calib(dev, 2, nsteps, speed)` | 19 |
| `CSUB EnterMeasurementMode` | `enter_measurement_mode(dev)` | 11 |
| `CSUB ExitMeasurementMode` | `exit_measurement_mode(dev)` | 12 |
| `CSUB PowerOff` | `power_off(dev)` | 10 |

`StartMove2` hardcodes −500,000.  `move_all_axes_to(dev, nsteps, speed)` is
parameterized: Julia reads GP 53/54/55, computes per-axis absolute targets
(`calib_pos − nsteps`), writes them to GP 59/60/61, and triggers command 9.

* * *

## Julia interface — tmcl_control_layer.jl

`tmcl_control_layer.jl` wraps `TrinamicMotionControl.jl` and exposes every board
routine as a named Julia function.  Two TMCL opcodes are used:

| TMCL opcode | Julia call | Direction |
|-------------|-----------|----------|
| SGP (9) | `set_global_parameter(dev, gp, value)` | Julia → board |
| GGP (10) | `get_global_parameter(dev, gp)` | board → Julia |

`wait_for_idle(dev)` polls GP 10 every 100 ms until the board clears it to 0
(timeout 60 s).  **Always call it after every command** — the board is still
executing its routine while GP 10 ≠ 0.

### Hard stop detection in StartMove

When `move_all_axes_to` is running (cmd 9), the `MonitorLoop` on the board polls both `AP 8` (target reached) and `AP 3` (actual velocity) for each axis on every iteration. If any axis reaches velocity = 0 before `AP 8` is set — whether from an external stop or because the motor stalled — `StopAllAxes` is triggered:

1. `SAP 17,x, 1,000,000` — boost deceleration on all axes for a fast controlled stop
2. `MST 0/1/2` — stop all motors
3. Poll `AP 3` per axis until velocity = 0 (confirm fully stopped)
4. Wait 20 ticks for mechanical settling
5. `AAP 17,x` — restore normal deceleration from `GP_MAX_DECELERATION`
6. `GAP 209,N; AAP 1,N; AAP 0,N` (for each axis) — sync the ramp generator and CL target to the actual encoder position
7. `SGP 10, 2, 0` — clear GP10; `wait_for_idle` in Julia unblocks normally

**Step 6 (target sync) is critical for direction changes after a hard stop.** Without it, `AP 0` (the CL target register) still points at the original destination after `MST`. When the next move starts, the CL controller fights the new commanded direction to drive toward the old target — the sled cannot move in the opposite direction. With target sync, `AP 0` is set to the actual encoder position so the CL controller sees zero error and the next move starts cleanly in any direction.

`StopAllAxes` also fires when a move completes normally (velocity reaches 0 at the target, just before `AP 8` is set in the same poll cycle). In that case the target sync is a no-op (AP 0 already matches the encoder), so normal completions are unaffected.

After a hard stop, Julia can send any new command immediately — including a move in the opposite direction — and the board returns to `MainLoop` with all parameters restored.

**Verified test — hard stop then direction change:**

After `calibrate!` (calibration positions: ax0 = 410,368 · ax1 = 410,033 · ax2 = 410,881), `move_all_axes_to_cm(dev, 6, ...)` was sent. Axis 2 was stopped by hand mid-move (hard stop at ~5.35 cm above block — encoder = (−138,420 · −138,754 · −135,295), giving 548,788 · 548,787 · 546,176 usteps above block respectively, inter-sled deviation 2,612 usteps = 0.255 mm). Then `move_all_axes_to_cm(dev, 2, ...)` was sent to move down to 2 cm above the block:

| Sled | Encoder pos after moving to 2 cm | Steps above calib block | Error from 2 cm target |
|------|----------------------------------|------------------------|------------------------|
| 0    | 204,441                          | 410,368 − 204,441 = **205,927** | **+1,127 usteps = +0.110 mm** |
| 1    | 204,081                          | 410,033 − 204,081 = **205,952** | **+1,152 usteps = +0.113 mm** |
| 2    | 206,106                          | 410,881 − 206,106 = **204,775** | −25 usteps = −0.002 mm |

Direction change after hard stop confirmed working. However, axes 0 and 1 overshot by ~1,150 usteps (~0.11 mm) — they stopped about 0.11 mm above the 2 cm target. Axis 2 (the actually hard-stopped sled) landed within 25 usteps.

**Why the ~0.11 mm error on direction change:** `StopAllAxes` syncs the CL target to actual position but does not flush the CL I-term (no CL cycle). The residual I-term from the upward move opposes the new downward move, causing axes to stop slightly short of the downward target. This effect is absent on same-direction moves (which achieve <50 ustep, 0.005mm deviation). **For precise positioning after a hard stop, completing the motion to the target in the original direction before reversing gives better accuracy.** The direction-change scenario is functional but introduces a ~0.11 mm systematic offset.

**AP 8 (Position Reached flag) behavior after StopAllAxes:** after the hard stop and target sync, AP 8 reports **1 (target reached)** — because `AAP 0,N` set the CL target to the actual position, so the CL controller sees zero error and the ramp generator considers itself at its destination. This contrasts with calibration hard stops (where the target was 1,000,000 and the sled stopped at ~410,000 — AP 8 correctly shows 0).

`enter_measurement_mode` called after this direction-change sequence: **worked successfully**. Drift: axis0 = +113, axis1 = −39, axis2 = +153 usteps (mixed directions; smaller magnitude than the 128–245 ustep range from other positions, suggesting drift varies with sled height and mechanical state).

Board state at the time of hard stop: voltage = 23.6 V, temperature = 39 °C, run current = 25%, standby = 8%, CL ENABLED on all axes.

* * *

## Startup scenarios

### Scenario A — Full power loss (`After_UnplugBoard.jl`)

**When this applies:** the board was fully unplugged, OR the red button was pressed
**and** the USB cable was also disconnected (or the PC was off).  In both cases the
MCU RAM is cleared — there is no USB supply keeping the logic alive — so everything
is lost: the TMCL program is gone, encoder zero reference is gone, and all AP values
(encoder positions, CL state, currents) are gone.  Only the EEPROM-backed calibration
positions (GP 53/54/55) could technically survive, but without a valid encoder zero
reference they are meaningless.  **Sleds must be above the calibration blocks before
running this.**

```julia
# 1. Load TMCMCode_newversion.tmc onto the board via TMCL-IDE (Creator Mode → upload)

# 2. Run After_UnplugBoard.jl
dev = connect_board(BOARD_IP, BOARD_PORT)
sleep(2.0)

# Verify state: random values expected, CL must be DISABLED
read_axis_status(dev)
read_closed_loop_status(dev)    # → DISABLED (firmware disabled on startup)

startup!(dev)                   # PowerOn → StartInit → DisableCL → EnableCL

# Set the encoder zero at the current sled positions — ONCE ONLY after unplugging
RefZero_run_only_once_after_unplugging_board!(dev)

read_closed_loop_status(dev)    # → ENABLED

calibrate!(dev)                 # all 3 axes descend → stall → positions saved to EEPROM

# Move the 3 axis
const MOVE_CM    = 5.0   # cm above calibration block
const SPEED_CM_S = 0.5   # cm/s (= 5 mm/s = 51,200 usteps/s)
move_all_axes_to_cm(dev, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)
```

**Why `RefZero` must only be called once after unplugging:**
`ReferenceZero` (GP 10 = 5) resets the encoder to 0 at the current sled positions
and syncs actual and target registers — giving the CL controller a clean zero
reference.  Calling it again after calibration would reset the origin to the block
positions, corrupting the coordinate system and breaking hard-stop detection.

**Verified measured behavior — full USB unplug + red button press:**

| State | calib ax0 | calib ax1 | calib ax2 | encoder ax0 | encoder ax1 | encoder ax2 | CL |
|-------|-----------|-----------|-----------|-------------|-------------|-------------|----|
| After full unplug (USB + power off) + reload TMCL | 292,831 | 326,035 | 301,264 | **−4** | **−2** | **+1** | DISABLED |
| After `startup!` | 292,831 | 326,035 | 301,264 | 124 | 126 | 129 | **ENABLED** |
| After `RefZero` | 292,831 | 326,035 | 301,264 | **0** | **0** | **0** | ENABLED |
| After `calibrate!` | 409,344 | 409,856 | 409,728 | 409,369 | 409,856 | 409,676 | ENABLED |

Encoder positions (−4, −2, +1) after full power loss confirm the MCU RAM was completely cleared — the encoder values are essentially zero (the sled positions at the time the previous session's `RefZero` was called). Calibration positions (292,831 · 326,035 · 301,264) survived exactly in EEPROM. After `RefZero` sets the new zero reference and `calibrate!` runs, the system is fully operational with fresh calib positions. Note that the new calib positions (~409k usteps) differ from the EEPROM-saved ones because `RefZero` established a new zero reference at the sled positions after restart, so the block distances are measured from that new origin.

* * *

### Scenario B — Red button pressed and unpressed, USB still connected (`AfterRedButton_CodeLooping.jl`)

**When this applies:** the red button was pressed and unpressed **while the USB cable
remained connected to the PC** (the TMCL program was still looping on the board at the moment of the press).
Because USB keeps the MCU logic supply alive, the MCU RAM is never cleared — encoder
positions, calibration positions, and CL PID parameters all survive.  The TMCL
program restarts from the top, runs the safety init (disables CL, zeros currents),
and re-enters the MainLoop.

**If `end_program` was called before pressing the red button:** the loop is stopped
only for the current session.  After a red-button press/unpress or a full power cycle,
the TMCL program will auto-start again from EEPROM as normal — `end_program` has no
effect on the auto-start setting.  To permanently prevent auto-start across power
cycles, load and execute `DisableAutostart.tmc` once via TMCL-IDE (`SGP 77,0,0`).

**Verified measured behavior:**

| State | calib ax0 | calib ax1 | calib ax2 | encoder ax0 | encoder ax1 | encoder ax2 | CL |
|-------|-----------|-----------|-----------|-------------|-------------|-------------|----|
| Before red button (code looping, sleds up) | 292,563 | 326,073 | 300,237 | −207,405 | −173,921 | −199,756 | **ENABLED** |
| After press + unpress red button | 292,563 | 326,073 | 300,237 | −207,405 | −173,895 | −199,244 | **DISABLED** |
| After `startup!` | 292,563 | 326,073 | 300,237 | −207,277 | −173,741 | −198,891 | **ENABLED** |
| After `calibrate!` | 292,819 | 326,074 | 300,335 | 292,819 | 326,074 | 300,335 | ENABLED |

Encoder positions drift slightly (0 to ~500 usteps ≈ 0.05 mm) during the red-button
period because CL is inactive and the sled is no longer actively held.  This is
normal.  After `calibrate!`, encoder positions match calibration positions exactly
— both columns show the same values.

**Second verified instance (USB connected throughout, sleds at various heights):**

| State | calib ax0 | calib ax1 | calib ax2 | encoder ax0 | encoder ax1 | encoder ax2 | CL |
|-------|-----------|-----------|-----------|-------------|-------------|-------------|----|
| After red button press + unpress (code was looping) | 410,446 | 410,070 | 409,856 | 103,246 | 102,870 | −104,730 | **DISABLED** |
| After `startup!` | 410,446 | 410,070 | 409,856 | 103,487 | 103,205 | −104,599 | **ENABLED** |
| After `calibrate!` | 410,533 | 410,021 | 409,807 | 410,533 | 410,021 | 409,807 | ENABLED |

Encoder positions (103k · 103k · −105k) confirm RAM survived — the sleds were at different heights (axes 0/1 were below the zero reference, axis 2 was above it). Calibration positions (410,446 · 410,070 · 409,856) survived in both EEPROM and RAM. After `calibrate!`, all three encoder positions match calib positions exactly.

Drift introduced by `startup!` (CL disable/enable cycle): ax0 = +241 usteps (0.024 mm) · ax1 = +335 usteps (0.033 mm) · ax2 = +131 usteps (0.013 mm). Range: 131–335 usteps (0.013–0.033 mm), all downward (toward calibration block).

This drift could in principle be eliminated by removing the `SAP 129, x, 0` lines
from the safety-init block at the top of `TMCMCode_newversion.tmc`, so that CL
remains enabled when the board restarts after a red-button press.  However, this
is intentionally not done because it would be dangerous:

- When the red button is pressed, motor power is cut abruptly.  The CL controller
  was actively driving the motor at the moment of cut; its integrator has accumulated
  error and its last commanded target is still stored in AP 0.
- When the red button is released and motor power returns, a CL controller that was
  never disabled would immediately command maximum current to drive the sled back to
  that target — a sudden, uncontrolled movement with no warning.
- The operator releasing the red button expects the system to be stationary and
  inert.  An emergency stop that re-energizes the motors automatically on release
  defeats the purpose of the stop.

Disabling CL in the safety init ensures that when power returns the sleds stay
exactly where they are until the operator explicitly calls `startup!` to restore
controlled motion.

```julia
dev = connect_board(BOARD_IP, BOARD_PORT)
sleep(2.0)

# Calib positions should still be present; encoder may have drifted; CL is DISABLED
read_axis_status(dev)
read_closed_loop_status(dev)

startup!(dev)                   # PowerOn → StartInit → DisableCL → EnableCL
                                # DO NOT call RefZero — encoder zero reference is still valid

read_axis_status(dev)
read_closed_loop_status(dev)    # → ENABLED

# Recalibrate (safe to run as many times as needed)
calibrate!(dev)

# Move the 3 axis
const MOVE_CM    = 5.0   # cm above calibration block
const SPEED_CM_S = 0.5   # cm/s (= 5 mm/s = 51,200 usteps/s)
move_all_axes_to_cm(dev, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)

# enter_measurement_mode(dev); wait_for_idle(dev)           # de-energize motors
# ... acquire data ...
# end_measurement!(dev)                                     # restore currents

shutdown!(dev)      # MST all, disable CL, zero currents
end_program(dev)    # stop the TMCL loop on the board for the current sesion but not after pressing and unpressing red button or after powering off the board
```

* * *

## Calibration and encoder zero — key rules

1. **`ReferenceZero` is only called once after unplugging the board (or with the red button pressed plus USB disconnected i.e. board unpowered)**, while sleds are
   above the blocks.  It sets encoder = 0 at the current sled positions.  After this,
   the zero reference is valid for the lifetime of the power-on session.

2. **`calibrate!` can be re-run as many times as needed** within a session.
   It descends all 3 axes simultaneously to their mechanical stops, saves encoder
   positions at each stop to GP 53/54/55, and writes them to EEPROM.

3. **After `calibrate!`, `calib_pos == encoder_pos` exactly.**
   `read_axis_status` showing identical values for both columns confirms a clean calibration.

4. **Calibration positions survive a red-button press/unpress (with USB connected)** (EEPROM).
   Calibration positions (GP 53/54/55, EEPROM-backed) **do** survive a full power loss.
However, the encoder zero reference (RAM) is lost — so although the EEPROM values are
still readable after unplugging, they are meaningless until `RefZero` is called to
establish a new zero reference and `calibrate!` is re-run to record new block positions
relative to that reference.

5. **Never call `reference_zero` after calibration.**  The CL controller's internal
   commutation state would no longer match the new encoder = 0 reference, causing
   incorrect hard-stop detection and erratic motion.

* * *

## Measurement mode — EnterMeasurementMode / ExitMeasurementMode

`EnterMeasurementMode` (command 11) de-energizes all motors for low-noise HPGe acquisition:
1. MST all axes.
2. Syncs CL target (`AAP 0`) to current encoder (`GAP 209`) for each axis — prevents the
   CL controller from fighting to return to an old move target when re-enabled.
3. Disables closed-loop on all axes (`DisableClosedLoop_Routine`) — flushes the accumulated
   I-term from any prior hard stop or prolonged stall so the integrator starts clean.
4. Immediately re-enables closed-loop (`EnableClosedLoop_Routine`) — clean integrator, target
   already synced to actual, so CL commands ~0 correction current.
5. Waits 50 ticks for CL to stabilise at the current position.
6. Sets run current (`SAP 6`) and standby current (`SAP 7`) to 0.
7. Waits 1000 ticks for complete electrical settling before measurement begins.

`ExitMeasurementMode` (command 12) restores the motion system:
1. Re-syncs ramp generator (`AAP 1`) and CL target (`AAP 0`) to the current encoder
   position for each axis — accounts for any sled drift during measurement and prevents
   oscillation when CL resumes driving a non-zero error.
2. Restores run current = 25 and standby current = 8.
3. Waits 50 ticks for CL to stabilise.

Note: `end_measurement!` in Julia uses SAP (direct axis parameter write) rather than
AAP/GGP to restore currents, because AAP/GGP is unreliable with CL active.

**Observed encoder drift during `enter_measurement_mode`:** a small encoder drift is consistently measured between the positions recorded before and after the call. Two measurements at different sled heights:

*At ~4 cm above block:*

| Axis | Encoder before | Encoder after | Drift |
|------|---------------|--------------|-------|
| 0    | 1,024         | 1,152        | **+128 usteps** |
| 1    | 486           | 640          | **+154 usteps** |
| 2    | 1,254         | 1,408        | **+154 usteps** |

*At ~3 cm above block:*

| Axis | Encoder before | Encoder after | Drift |
|------|---------------|--------------|-------|
| 0    | 103,359       | 103,552      | **+193 usteps** |
| 1    | 102,795       | 103,040      | **+245 usteps** |
| 2    | 102,581       | 102,784      | **+203 usteps** |

A third measurement, taken at ~2 cm after a hard stop + direction change sequence:

| Axis | Encoder before | Encoder after | Drift |
|------|---------------|--------------|-------|
| 0    | 204,441       | 204,554      | **+113 usteps** |
| 1    | 204,081       | 204,042      | **−39 usteps** |
| 2    | 206,106       | 206,259      | **+153 usteps** |

Axis 1 drifted slightly upward (away from block) — mixed direction, smaller magnitude than other measurements.

Drift range across all measurements: **−39 to +245 usteps (−0.004 to +0.024 mm)**. Direction is usually downward (toward block) but can vary at different sled heights and mechanical states. Magnitude is always sub-0.025 mm. The inter-sled deviation impact is small: in the 3 cm test, deviation before = 52 usteps, after = 42 usteps (drift was nearly uniform across all three axes).

This drift comes from the **1000-tick zero-current window** (step 7 above), during
which the motors are fully de-energized and the lead screws bear the sled weight
passively. The CL disable/enable cycle (steps 3–4) does **not** cause drift —
`DisableClosedLoop_Routine` only sets AP 129 = 0 (disables the feedback loop) without
zeroing the run or standby current, so the motors remain energized and holding
throughout the ~50 ms cycle. De-energization only happens at step 6 (`SAP 6/7 = 0`),
after which the self-locking lead screws resist but do not fully prevent small
gravitational settling over the 1000-tick (~1 s) window. If drift-free positioning
is required, call `exit_measurement_mode` (which re-syncs the target to the drifted
encoder position) before any subsequent move command.

After `exit_measurement_mode` the system is fully operational — CL is still enabled
and currents are restored. Because the sleds were moved upward before entering
measurement mode they are above the calibration blocks, so `calibrate!` can be called
again at any point after `exit_measurement_mode` without any additional steps.

* * *

## Red button and hard stop — end-to-end verification

Full test `TMCMCode_newversion.tmc` loaded via TMCL-IDE:

**Red button test (USB connected throughout):**

| State | calib ax0 | calib ax1 | calib ax2 | encoder ax0 | encoder ax1 | encoder ax2 | CL |
|-------|-----------|-----------|-----------|-------------|-------------|-------------|----|
| Before red button (code looping, sleds up) | 292563 | 326073 | 300237 | −207405 | −173921 | −199756 | ENABLED |
| After press + unpress | 292563 | 326073 | 300237 | −207405 | −173895 | −199244 | **DISABLED** |
| After `startup!` | 292563 | 326073 | 300237 | −207277 | −173741 | −198891 | **ENABLED** |
| After `calibrate!` | 292819 | 326074 | 300335 | 292819 | 326074 | 300335 | ENABLED |

Drift after red button plus startup (this is due to disabling and enabling closed loop in startup! routine): ~500 usteps (≈ 0.05 mm).

**Shutdown verification:** `shutdown!` zeroed run and standby currents (AP 6/7 = 0, confirmed via `board_status`). `end_program` stopped the TMCL loop; `is_program_running` returned `false`.

* * *

### Julia-driven hard stop test — `move_all_axes_to`, 600,000-step target, 2 consecutive hard stops

Setup: `TMCMCode_newversion.tmc`, `startup!` → `calibrate!`, then `move_all_axes_to(dev, 600_000, 51_200)`.
Hard stop triggered manually on axis 2 (mid-move), twice, then movement resumed to completion.

Calibration block positions: ax0 = 292,614 · ax1 = 326,073 · ax2 = 300,243

**After 1st hard stop (axis 2 stopped mid-move):**

| Sled | Encoder pos | Steps moved above calib |
|------|-------------|------------------------|
| 0    | 89,580      | 292,614 − 89,580 = **203,034** |
| 1    | 123,014     | 326,073 − 123,014 = **203,059** |
| 2    | 100,077     | 300,243 − 100,077 = **200,166** |

Sled deviation: 203,059 − 200,166 = **2,893 usteps = 0.28 mm**

**After 2nd hard stop (axis 2 stopped again, movement resumed after 1st stop):**

| Sled | Encoder pos | Steps moved above calib |
|------|-------------|------------------------|
| 0    | −56,954     | 292,614 + 56,954 = **349,568** |
| 1    | −23,546     | 326,073 + 23,546 = **349,619** |
| 2    | −43,437     | 300,243 + 43,437 = **343,680** |

Sled deviation (accumulated, 2 stops): 349,619 − 343,680 = **5,939 usteps = 0.58 mm**

**After completing movement to 600,000 steps above calib:**

| Sled | Encoder pos | Steps moved above calib |
|------|-------------|------------------------|
| 0    | −307,374    | 292,614 + 307,374 = **599,988** |
| 1    | −273,940    | 326,073 + 273,940 = **600,013** |
| 2    | −299,795    | 300,243 + 299,795 = **600,038** |

Sled deviation after completion: 600,038 − 599,988 = **50 usteps = 0.005 mm**

**Key result:** The accumulated sled misalignment from 2 hard stops (5,939 usteps / 0.58 mm) disappears almost entirely once the movement completes normally to the programmed target. Final inter-sled deviation is 50 usteps (0.005 mm) — two orders of magnitude smaller than the mid-stop deviation.

* * *

### Hard stop + resume accuracy — Scenario A (full USB unplug recovery)

Setup: full USB unplug → reload TMCMCode_newversion.tmc → `startup!` → `RefZero` → `calibrate!` (new calib: ax0 = 409,344 · ax1 = 409,856 · ax2 = 409,728). Then `move_all_axes_to_cm(dev, 2.0, 0.5)`:

| Sled | Encoder pos at 2 cm | Steps above calib | Distance | Error from 2 cm target |
|------|---------------------|------------------|---------|------------------------|
| 0    | 204,569             | 409,344 − 204,569 = **204,775** | 1.9997 cm | −25 usteps (−0.002 mm) |
| 1    | 205,081             | 409,856 − 205,081 = **204,775** | 1.9997 cm | −25 usteps (−0.002 mm) |
| 2    | 204,953             | 409,728 − 204,953 = **204,775** | 1.9997 cm | −25 usteps (−0.002 mm) |

Inter-sled deviation: **0 usteps** — all three axes at exactly the same distance above their respective blocks. All land 25 usteps (0.002 mm) short of the 204,800-ustep (2 cm) target.

Then `move_all_axes_to_cm(dev, 5.0, 0.5)`. Axis 1 hard stopped mid-move:

| Sled | Encoder at hard stop | Distance traveled from 2 cm start |
|------|---------------------|----------------------------------|
| 0    | −33,818             | 204,569 + 33,818 = **238,387** usteps |
| 1    | −30,592             | 205,081 + 30,592 = **235,673** usteps |
| 2    | −33,408             | 204,953 + 33,408 = **238,361** usteps |

Inter-sled deviation at hard stop: 238,387 − 235,673 = **2,714 usteps = 0.27 mm**

After resuming and completing the move to 5 cm:

| Sled | Encoder at 5 cm | Additional steps from hard-stop position | Total steps from 2 cm |
|------|----------------|------------------------------------------|----------------------|
| 0    | −102,656        | 102,656 − 33,818 = 68,838 | 204,569 + 102,656 = **307,225** |
| 1    | −102,144        | 102,144 − 30,592 = 71,552 | 205,081 + 102,144 = **307,225** |
| 2    | −102,272        | 102,272 − 33,408 = 68,864 | 204,953 + 102,272 = **307,225** |

All three axes traveled exactly 307,225 usteps from their 2 cm positions. Final positions above calib:
- axis0: 409,344 − (−102,656) = **512,000 = 5 cm exactly** ✓
- axis1: 409,856 − (−102,144) = **512,000 = 5 cm exactly** ✓
- axis2: 409,728 − (−102,272) = **512,000 = 5 cm exactly** ✓

Inter-sled deviation after completion: **0 usteps**. The mid-stop misalignment of 2,714 usteps (0.27 mm) is fully corrected when the move completes to the programmed target. Board state: voltage = 23.6 V, temperature = 43 °C, CL ENABLED.

* * *

### Hard stop + resume accuracy — Scenario B (red button with USB connected)

Setup: red button press + unpress (USB connected) → `startup!` → `calibrate!` (calib: ax0 = 410,533 · ax1 = 410,021 · ax2 = 409,807). Voltage at test time: 23.5 V (slightly lower than usual).

`move_all_axes_to_cm(dev, 5.0, 0.5)`. Axis 2 hard stopped mid-move:

| Sled | Encoder at hard stop | Steps above calib block |
|------|---------------------|------------------------|
| 0    | 200,767             | 410,533 − 200,767 = **209,766** |
| 1    | 200,280             | 410,021 − 200,280 = **209,741** |
| 2    | 202,857             | 409,807 − 202,857 = **206,950** |

Inter-sled deviation at hard stop: 209,766 − 206,950 = **2,816 usteps = 0.275 mm**

After resuming and completing the move to 5 cm:

| Sled | Encoder at 5 cm | Steps above calib block | Distance |
|------|----------------|------------------------|---------|
| 0    | −101,441        | 410,533 + 101,441 = **511,974** | 4.9997 cm |
| 1    | −101,979        | 410,021 + 101,979 = **512,000** | **5.0000 cm** |
| 2    | −102,193        | 409,807 + 102,193 = **512,000** | **5.0000 cm** |

Inter-sled deviation after completion: **26 usteps = 0.003 mm**. The 2,816-ustep hard-stop misalignment reduces to 26 usteps once the move finishes.

Then `move_all_axes_to_cm(dev, 3.0, 0.5)` (going back down from 5 cm):

| Sled | Encoder at 3 cm | Steps above calib block | Distance |
|------|----------------|------------------------|---------|
| 0    | 103,359         | 410,533 − 103,359 = **307,174** | 2.9997 cm |
| 1    | 102,795         | 410,021 − 102,795 = **307,226** | 3.0003 cm |
| 2    | 102,581         | 409,807 − 102,581 = **307,226** | 3.0003 cm |

Inter-sled deviation: **52 usteps = 0.005 mm**. Board state: voltage = 23.6 V, temperature = 43 °C, CL ENABLED.

**`enter_measurement_mode` drift from 3 cm position:**

| Axis | Encoder before | Encoder after | Drift |
|------|---------------|--------------|-------|
| 0    | 103,359       | 103,552      | **+193 usteps** |
| 1    | 102,795       | 103,040      | **+245 usteps** |
| 2    | 102,581       | 102,784      | **+203 usteps** |

Sleds drifted toward the calibration block (encoder increased = downward). Maximum drift 245 usteps ≈ 0.024 mm. Inter-sled deviation before: 52 usteps; after: **42 usteps = 0.004 mm** — drift is not uniform but nearly so, and the inter-sled deviation actually improved slightly. Board state after: run current = 0, standby = 0, CL ENABLED.

This is the second drift measurement (compare with 128–154 usteps documented from a ~4 cm position). The larger values (193–245 usteps) at the 3 cm position suggest drift magnitude may vary with sled height or the state of the lead-screw preload, but both measurements are in the same order of magnitude (sub-0.025 mm). `end_measurement!` restores currents without changing encoder positions.

* * *

### Full workflow test — startup, calibrate, mixed single-axis and all-axis moves, measurement mode

Setup: TMCMCode_newversion.tmc reloaded after red-button press. `startup!` → `calibrate!`.

Calibration block positions: ax0 = 292,835 · ax1 = 326,039 · ax2 = 300,286

**Move all 3 axes simultaneously to 2 cm above calibration blocks:**

`move_all_axes_to_cm(dev, 2.0, 0.5)` → target = 2 cm = 204,800 usteps above each block.

| Sled | Encoder pos | Steps above calib block | Distance |
|------|-------------|------------------------|---------|
| 0    | 88,035      | 292,835 − 88,035 = **204,800** | **2.0000 cm** |
| 1    | 121,264     | 326,039 − 121,264 = **204,775** | **1.9998 cm** |
| 2    | 95,511      | 300,286 − 95,511 = **204,775** | **1.9998 cm** |

All three axes within 25 usteps (0.002 mm) of the 204,800-ustep target. Inter-sled deviation: **25 usteps = 0.002 mm**.

**Move axes 0, 1, 2 independently to 4 cm (sequential per-axis commands):**

`move_axis_above_calib_cm(dev, 0, 4.0, 0.5)` → axis 0 moves; axes 1 and 2 hold position.
`move_axis_above_calib_cm(dev, 1, 4.0, 0.5)` → axis 1 moves; axes 0 and 2 hold position.
`move_axis_above_calib_cm(dev, 2, 4.0, 0.5)` → axis 2 moves; axes 0 and 1 hold position.

Target = 4 cm = 409,600 usteps above each block.

| Sled | Encoder pos after individual move | Steps above calib block | Distance |
|------|----------------------------------|------------------------|---------|
| 0    | −116,765                         | 292,835 + 116,765 = **409,600** | **4.0000 cm** |
| 1    | −83,561                          | 326,039 + 83,561 = **409,600** | **4.0000 cm** |
| 2    | −109,314                         | 300,286 + 109,314 = **409,600** | **4.0000 cm** |

All three axes hit exactly 409,600 usteps = 4 cm. Each stationary axis stayed at its prior position while the active axis moved — confirmed by reading encoder after each command.

Board state after per-axis moves: voltage = 23.6 V, temperature = 40 °C, run current = 25%, standby = 8%, CL ENABLED.

**Move all 3 axes simultaneously from 4 cm to 6 cm:**

`move_all_axes_to_cm(dev, 6.0, 0.5)` — axes start from the same 4 cm position, move together.

| Sled | Encoder pos | Steps above calib block | Distance |
|------|-------------|------------------------|---------|
| 0    | −321,565    | 292,835 + 321,565 = **614,400** | **6.0000 cm** |
| 1    | −288,361    | 326,039 + 288,361 = **614,400** | **6.0000 cm** |
| 2    | −314,089    | 300,286 + 314,089 = **614,375** | **5.9998 cm** |

Inter-sled deviation at 6 cm: **25 usteps = 0.002 mm**.

Board state: voltage = 23.6 V, temperature = 41 °C, run current = 25%, standby = 8%, CL ENABLED.

**`enter_measurement_mode` — got stuck in this test.**

In this test session, `enter_measurement_mode(dev); wait_for_idle(dev)` hung indefinitely. The version of `EnterMeasurementMode` active at the time polled `AP 3` (actual velocity) until each axis confirmed velocity = 0 after MST. After a hard stop, the accumulated CL I-term causes the motor to keep fighting against the mechanical stop even after MST — velocity never settles to 0, and the poll loop never exits. Fix: add a CL disable/enable cycle (`CSUB DisableClosedLoop_Routine / CSUB EnableClosedLoop_Routine`) before zeroing the currents to flush the I-term. Confirmed working in the subsequent session (15 June 2026) — see [below](#full-workflow-with-measurement-mode----complete-startup-to-shutdown) and [Measurement mode](#measurement-mode----entermeasurementmode--exitmeasurementmode).

* * *

### Full workflow with measurement mode — complete startup to shutdown

Setup: TMCMCode_newversion.tmc loaded (auto-start). `startup!` → `calibrate!`.

Calibration block positions: ax0 = 410,597 · ax1 = 410,085 · ax2 = 410,801 (encoder = calib exactly after `calibrate!`).

**Move all 3 axes to 0.5 cm:**

| Sled | Encoder pos | Steps above calib block | Distance | Error from target |
|------|-------------|------------------------|---------|-------------------|
| 0    | 359,423     | 410,597 − 359,423 = **51,174** | **0.4997 cm** | −26 usteps (−0.003 mm) |
| 1    | 358,911     | 410,085 − 358,911 = **51,174** | **0.4997 cm** | −26 usteps (−0.003 mm) |
| 2    | 359,601     | 410,801 − 359,601 = **51,200** | **0.5000 cm** | 0 usteps |

Inter-sled deviation: **26 usteps = 0.003 mm**. Board state: voltage = 23.6 V, temperature = 39 °C, CL ENABLED.

**Move all 3 axes to 2 cm:**

| Sled | Encoder pos | Steps above calib block | Distance | Error from target |
|------|-------------|------------------------|---------|-------------------|
| 0    | 205,669     | 410,597 − 205,669 = **204,928** | **2.0013 cm** | +128 usteps (+0.013 mm) |
| 1    | 205,157     | 410,085 − 205,157 = **204,928** | **2.0013 cm** | +128 usteps (+0.013 mm) |
| 2    | 205,848     | 410,801 − 205,848 = **204,953** | **2.0015 cm** | +153 usteps (+0.015 mm) |

Inter-sled deviation: **25 usteps = 0.002 mm**.

**Move all 3 axes to 4 cm:**

| Sled | Encoder pos | Steps above calib block | Distance | Error from target |
|------|-------------|------------------------|---------|-------------------|
| 0    | 997         | 410,597 − 997 = **409,600** | **4.0000 cm** | 0 usteps |
| 1    | 511         | 410,085 − 511 = **409,574** | **3.9997 cm** | −26 usteps (−0.003 mm) |
| 2    | 1,227       | 410,801 − 1,227 = **409,574** | **3.9997 cm** | −26 usteps (−0.003 mm) |

Inter-sled deviation: **26 usteps = 0.003 mm**. Board state: voltage = 23.6 V, temperature = 40 °C, CL ENABLED.

**`enter_measurement_mode(dev)` — two verified measurements:**

*At 4 cm (this test):*

| Axis | Encoder before | Encoder after | Drift |
|------|---------------|--------------|-------|
| 0    | 997           | 1,152        | **+155 usteps (+0.015 mm)** |
| 1    | 511           | 640          | **+129 usteps (+0.013 mm)** |
| 2    | 1,227         | 1,383        | **+156 usteps (+0.015 mm)** |

Board state after: run current = 0, standby = 0, CL ENABLED, voltage = 23.6 V, temperature = 40 °C.

*At 3 cm (Scenario B test — see [Hard stop + resume accuracy — Scenario B](#hard-stop--resume-accuracy----scenario-b-red-button-with-usb-connected)):*

| Axis | Encoder before | Encoder after | Drift |
|------|---------------|--------------|-------|
| 0    | 103,359       | 103,552      | **+193 usteps (+0.019 mm)** |
| 1    | 102,795       | 103,040      | **+245 usteps (+0.024 mm)** |
| 2    | 102,581       | 102,784      | **+203 usteps (+0.020 mm)** |

Drift range across both measurements: **+129 to +245 usteps (+0.013 to +0.024 mm)**, all downward (toward calibration block). Larger drift observed at 3 cm than at 4 cm, consistent with height-dependent mechanical settling.

**`end_measurement!(dev)` — currents restored correctly.**

Encoder positions unchanged: (1,152 · 640 · 1,383) — identical to post-enter values. CL ENABLED. Run current = 25, standby = 8, confirmed via `board_status` and `read_closed_loop_status`.

**`shutdown!(dev)` → `end_program(dev)` — clean shutdown verified.**

`board_status` after shutdown: run current = 0, standby = 0, motion GP parameters preserved. `end_program(dev)` stopped the TMCL loop; `is_program_running(dev)` returned `false` ("No TMCL program running — Ping was not processed"). Red button then pressed.

* * *

### Why hard stop → direction change previously failed (and what fixed it)

Before the target-sync fix, `StopAllAxes` called `MST` on all axes but did **not** update `AP 0` (the CL target register). After `MST`, the ramp generator stopped, but `AP 0` still held the original destination — for example, 6 cm above the block. The CL controller remained active and continued to fight toward that old target. When Julia then sent a new `move_all_axes_to` in the opposite direction (e.g., down to 2 cm), the new ramp generator target (in AP 1) conflicted with the old CL target still in AP 0. The CL controller and the ramp generator pulled in opposite directions; the motor could not establish motion.

**Fix:** after all axes confirm velocity = 0, execute `GAP 209,N; AAP 1,N; AAP 0,N` for each axis. This writes the actual encoder position into both the ramp generator (AP 1) and the CL target (AP 0), so the CL controller sees zero error at the current position. The next move then starts from a consistent, fight-free state regardless of direction.

**Why a CL I-term flush (disable/enable cycle) is not needed in `StopAllAxes`:** `MonitorLoop` detects a hard stop within ~1 ms (one poll iteration). The I-term has had virtually no time to accumulate significant error at that moment. Target sync alone is sufficient. A CL cycle is only needed when the motor has been stalling for seconds (e.g., the 60-second timeout in the old `MoveAxis0/1/2` implementation, or during `EnterMeasurementMode` where CL is active with zero current for 1000 ticks). In `MoveAxis0AboveCalib/1/2AboveCalib`, the per-axis CL flush is retained because those routines can sit stalled against a mechanical limit for an extended period before the monitoring loop catches it.

* * *

## Clean shutdown procedure

Before pressing the red button to power off, always run:

```julia
shutdown!(dev)      # MST all axes, disable CL, zero currents
end_program(dev)    # stop the TMCL loop on the board
```

After `end_program` the TMCL program stops looping for the current session only.
Pressing the red button (or any power cycle) will auto-restart the program from EEPROM
as normal — `end_program` has no effect on the auto-start setting.  To prevent
auto-restart across power cycles, load and run `DisableAutostart.tmc` once via TMCL-IDE.

If `shutdown!` is skipped, the next startup still works correctly because the firmware
disables CL and zeros currents on every program start.  Calling `shutdown!` first is
still best practice — it leaves the board in a known idle state and avoids the CL
controller being active at the moment of power loss.

* * *

## Default motion parameters

| Julia constant | Default value | Units | AP / GP |
|---------------|--------------|-------|--------|
| `DEFAULT_MAX_SPEED` | 51,200 | usteps/s | AP 4 / GP 4 |
| `DEFAULT_MAX_ACCELERATION` | 51,200 | usteps/s² | AP 5 / GP 5 |
| `DEFAULT_MAX_DECELERATION` | 51,200 | usteps/s² | AP 17 / GP 17 |
| `DEFAULT_MAX_CURRENT` | 25 | % of max | AP 6 / GP 6 |
| `DEFAULT_STANDBY_CURRENT` | 8 | % of max | AP 7 / GP 7 |
| `DEFAULT_ENCODER_RESOLUTION` | 2,000 | counts/rev | AP 210 / GP 210 |
| `DEFAULT_CL_GAMMA_VMIN` | 300,000 | usteps/s | AP 108 / GP 108 |
| `DEFAULT_CL_GAMMA_VMAX` | 600,000 | usteps/s | AP 109 / GP 109 |
| `DEFAULT_CL_MAXGAMMA` | 255 | — | AP 110 / GP 110 |
| `DEFAULT_CL_BETA` | 255 | — | AP 111 / GP 111 |
| `DEFAULT_CL_CURRENTMIN` | 50 | (internal units) | AP 113 / GP 113 |
| `DEFAULT_CL_CURRENTMAX` | 240 | (internal units) | AP 114 / GP 114 |
| `DEFAULT_CL_CORRECTION_VELOCITY_P` | 3,000 | — | AP 115 / GP 115 |
| `DEFAULT_CL_CORRECTION_VELOCITY_I` | 20 | — | AP 116 / GP 116 |
| `DEFAULT_CL_CORRECTION_VELOCITY_I_CLIP` | 10 | — | AP 117 / GP 117 |
| `DEFAULT_CL_CORRECTION_VELOCITY_DV_CLK` | 0 | — | AP 118 / GP 118 |
| `DEFAULT_CL_CORRECTION_VELOCITY_DV_CLIP` | 100,000 | usteps/s | AP 119 / GP 119 |
| `DEFAULT_CL_UPSCALE_DELAY` | 1,000 | ticks | AP 120 / GP 120 |
| `DEFAULT_CL_DOWNSCALE_DELAY` | 10,000 | ticks | AP 121 / GP 121 |
| `DEFAULT_CL_CORRECTION_POS` | 65,536 | usteps | AP 124 / GP 124 |
| `DEFAULT_CL_MAX_CORRECTION_TOLERANCE` | 100 | usteps | AP 125 / GP 125 |
| `DEFAULT_CL_STARTUP` | 25 | — | AP 126 / GP 126 |
| `DEFAULT_POS_WINDOW` | 100 | usteps | AP 134 / GP 134 |
| `DEFAULT_MAX_ENCODER_DEVIATION` | 1,000 | usteps | AP 212 / GP 212 |
| `DEFAULT_MAX_VELOCITY_DEVIATION` | 30,000 | usteps/s | AP 213 / GP 213 |

Scale: 1 motor turn = 5 mm = 51,200 microsteps → **1 ustep ≈ 0.097 µm**

`USTEPS_PER_MM = 10,240` / `USTEPS_PER_CM = 102,400` — used by the `_cm` function variants to convert distances
and speeds: `DEFAULT_MAX_SPEED` of 51,200 usteps/s = **5 mm/s = 0.5 cm/s**.

All defaults can be overridden via keyword arguments to `power_on(dev; ...)` and
`start_init(dev; ...)`.
