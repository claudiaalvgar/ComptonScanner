module TMCLControlLayer

export connect_board,
       set_global_parameter,
       get_global_parameter,
       wait_for_idle,
       read_supply_voltage,
       read_temperature,
       board_status,
       read_axis_status,
       power_on,
       power_off,
       start_init,
       disable_closed_loop,
       enable_closed_loop,
       reference_zero,
       calibrate_axis,
       calibrate_simultaneous,
       enter_measurement_mode,
       exit_measurement_mode,
       move_axis_absolute,
       move_all_axes_to,
       move_all_axes_to_cm,
       move_absolute_axis_to,
       move_axis_above_calib,
       move_axis_above_calib_cm,
       end_program,
       is_program_running,
       startup!,
       startup_loaded!,
       calibrate!,
       end_measurement!,
       shutdown!,
       read_closed_loop_status,
       RefZero_run_only_once_after_unplugging_board!

using TrinamicMotionControl
import TrinamicMotionControl: query, set_axis_parameter, get_axis_parameter

# ============================================================
# IMPORTANT CONSTANT
# ============================================================
#=
TMCL protocol: Julia writes to GP 10 (Bank 2) to trigger routines in the
running TMCL state machine. The board polls GP 10 in its MainLoop, dispatches
to the matching routine, and writes GP 10 = 0 on completion. Julia polls with
wait_for_idle() to know when the board is done.

TMCL command numbers: 9 = SGP, 10 = GGP, both use Bank 2.
=#
const GP_BANK = 2   # must match TMCMCode_newversion.tmc / TMCMTestLoop.tmc (Bank 2)

# ── GP Bank 2 address constants ───────────────────────────────────────────────
# Mirror the variable declarations at the top of the TMC scripts so every
# set_global_parameter / get_global_parameter call uses a readable name.
const GP_TARGET_POS                     = 0
const GP_ACTUAL_POS                     = 1
const GP_TARGET_SPEED                   = 2
const GP_ACTUAL_SPEED                   = 3
const GP_MAX_SPEED                      = 4
const GP_MAX_ACCELERATION               = 5
const GP_MAX_CURRENT                    = 6
const GP_STANDBY_CURRENT                = 7
const GP_TMCM_COMMAND                   = 10
const GP_MAX_DECELERATION               = 17
const GP_CALIB_POS_AXIS0                = 53
const GP_CALIB_POS_AXIS1                = 54
const GP_CALIB_POS_AXIS2                = 55
const GP_CALIB_DONE_AXIS0               = 56
const GP_CALIB_DONE_AXIS1               = 57
const GP_CALIB_DONE_AXIS2               = 58
const GP_MOVE_TARGET_AXIS0              = 59
const GP_MOVE_TARGET_AXIS1              = 60
const GP_MOVE_TARGET_AXIS2              = 61
const GP_CL_GAMMA_VMIN                  = 108
const GP_CL_GAMMA_VMAX                  = 109
const GP_CL_MAXGAMMA                    = 110
const GP_CL_BETA                        = 111
const GP_CL_CURRENTMIN                  = 113
const GP_CL_CURRENTMAX                  = 114
const GP_CL_CORRECTION_VELOCITY_P       = 115
const GP_CL_CORRECTION_VELOCITY_I       = 116
const GP_CL_CORRECTION_VELOCITY_I_CLIP  = 117
const GP_CL_CORRECTION_VELOCITY_DV_CLK  = 118
const GP_CL_CORRECTION_VELOCITY_DV_CLIP = 119
const GP_CL_UPSCALE_DELAY               = 120
const GP_CL_DOWNSCALE_DELAY             = 121
const GP_CL_CORRECTION_POS              = 124
const GP_CL_MAX_CORRECTION_TOLERANCE    = 125
const GP_CL_STARTUP                     = 126
const GP_POS_WINDOW                     = 134
const GP_ENCODER_POS                    = 209
const GP_ENCODER_RESOLUTION             = 210
const GP_MAX_ENCODER_DEVIATION          = 212
const GP_MAX_VELOCITY_DEVIATION         = 213

# ── Default parameter values ──────────────────────────────────────────────────
# Match the SGP static-init values in the TMC scripts.
# Override via keyword arguments on power_on / start_init.
# 1 motor revolution = 5 mm = 51,200 microsteps → 10,240 usteps/mm → 102,400 usteps/cm
const USTEPS_PER_MM = 10_240
const USTEPS_PER_CM = 102_400

const DEFAULT_ENCODER_RESOLUTION             = 2000
const DEFAULT_MAX_SPEED                      = 51_200
const DEFAULT_MAX_ACCELERATION               = 51_200
const DEFAULT_MAX_DECELERATION               = 51_200
const DEFAULT_MAX_CURRENT                    = 25
const DEFAULT_STANDBY_CURRENT                = 8
const DEFAULT_CL_GAMMA_VMIN                  = 300_000
const DEFAULT_CL_GAMMA_VMAX                  = 600_000
const DEFAULT_CL_MAXGAMMA                    = 255
const DEFAULT_CL_BETA                        = 255
const DEFAULT_CL_CURRENTMIN                  = 50
const DEFAULT_CL_CURRENTMAX                  = 240
const DEFAULT_CL_CORRECTION_VELOCITY_P       = 3000
const DEFAULT_CL_CORRECTION_VELOCITY_I       = 20
const DEFAULT_CL_CORRECTION_VELOCITY_I_CLIP  = 10
const DEFAULT_CL_CORRECTION_VELOCITY_DV_CLK  = 0
const DEFAULT_CL_CORRECTION_VELOCITY_DV_CLIP = 100_000
const DEFAULT_CL_UPSCALE_DELAY               = 1000
const DEFAULT_CL_DOWNSCALE_DELAY             = 10_000
const DEFAULT_CL_CORRECTION_POS              = 65_536
const DEFAULT_CL_MAX_CORRECTION_TOLERANCE    = 100
const DEFAULT_CL_STARTUP                     = 25
const DEFAULT_POS_WINDOW                     = 100
const DEFAULT_MAX_ENCODER_DEVIATION          = 1000
const DEFAULT_MAX_VELOCITY_DEVIATION         = 30_000

# ── Loaded-platform parameter values (~20 kg block) ──────────────────────────
# Self-locking lead screws hold position without current, so standby_current is
# unchanged.  The extra mass raises the torque needed to break static friction
# and sustain motion, so we raise max_current and slow the ramp.
# max_encoder_deviation / max_velocity_deviation are loosened because the motor
# lags the ramp generator more under load; tight limits trigger false stall stops.
const LOADED_MAX_CURRENT             = 40      # was 25 — raise torque ceiling
const LOADED_MAX_SPEED               = 25_600  # was 51_200 — half speed
const LOADED_MAX_ACCELERATION        = 10_240  # was 51_200 — 5× slower ramp start
const LOADED_MAX_DECELERATION        = 10_240  # was 51_200 — 5× slower ramp stop
const LOADED_MAX_ENCODER_DEVIATION   = 2_000   # was 1_000 — allow more lag under load
const LOADED_MAX_VELOCITY_DEVIATION  = 60_000  # was 30_000 — same reason

# ============================================================
# LOW LEVEL WRAPPERS
# ============================================================

"""
Set global parameter (SGP)
"""
function set_global_parameter(dev, gp::Int, value::Int)
    return query(dev, 9, gp, GP_BANK, value)
end

"""
Get global parameter (GGP)
"""
function get_global_parameter(dev, gp::Int)
    return query(dev, 10, gp, GP_BANK, 0)
end

# State machine commands — GP10 values match TMCMCode_newversion.tmc

"""
Write motion parameters to GP Bank 2, then trigger the board's PowerOn routine
(GP_TMCM_COMMAND = 1).  The board reads these GPs and applies them to all 3 axis
parameter registers (AP 4/5/6/7/17/210) via AAP, then syncs encoder→actual→target
atomically on the board (no network-latency snap risk).
Keyword arguments let you override individual parameters at call time.
"""
function power_on(dev;
        encoder_resolution = DEFAULT_ENCODER_RESOLUTION,
        max_speed          = DEFAULT_MAX_SPEED,
        max_acceleration   = DEFAULT_MAX_ACCELERATION,
        max_deceleration   = DEFAULT_MAX_DECELERATION,
        max_current        = DEFAULT_MAX_CURRENT,
        standby_current    = DEFAULT_STANDBY_CURRENT)
    set_global_parameter(dev, GP_ENCODER_RESOLUTION, encoder_resolution)
    set_global_parameter(dev, GP_MAX_SPEED,          max_speed)
    set_global_parameter(dev, GP_MAX_ACCELERATION,   max_acceleration)
    set_global_parameter(dev, GP_MAX_DECELERATION,   max_deceleration)
    set_global_parameter(dev, GP_MAX_CURRENT,        max_current)
    set_global_parameter(dev, GP_STANDBY_CURRENT,    standby_current)
    set_global_parameter(dev, GP_TMCM_COMMAND,       1)
end

"""
Write closed-loop PID parameters to GP Bank 2, then trigger the board's StartInit
routine (GP_TMCM_COMMAND = 2).  The board reads these GPs and applies them to all
3 axes via AAP.  Keyword arguments let you override individual parameters.
"""
function start_init(dev;
        cl_gamma_vmin                  = DEFAULT_CL_GAMMA_VMIN,
        cl_gamma_vmax                  = DEFAULT_CL_GAMMA_VMAX,
        cl_maxgamma                    = DEFAULT_CL_MAXGAMMA,
        cl_beta                        = DEFAULT_CL_BETA,
        cl_currentmin                  = DEFAULT_CL_CURRENTMIN,
        cl_currentmax                  = DEFAULT_CL_CURRENTMAX,
        cl_correction_velocity_p       = DEFAULT_CL_CORRECTION_VELOCITY_P,
        cl_correction_velocity_i       = DEFAULT_CL_CORRECTION_VELOCITY_I,
        cl_correction_velocity_i_clip  = DEFAULT_CL_CORRECTION_VELOCITY_I_CLIP,
        cl_correction_velocity_dv_clk  = DEFAULT_CL_CORRECTION_VELOCITY_DV_CLK,
        cl_correction_velocity_dv_clip = DEFAULT_CL_CORRECTION_VELOCITY_DV_CLIP,
        cl_upscale_delay               = DEFAULT_CL_UPSCALE_DELAY,
        cl_downscale_delay             = DEFAULT_CL_DOWNSCALE_DELAY,
        cl_correction_pos              = DEFAULT_CL_CORRECTION_POS,
        cl_max_correction_tolerance    = DEFAULT_CL_MAX_CORRECTION_TOLERANCE,
        cl_startup                     = DEFAULT_CL_STARTUP,
        pos_window                     = DEFAULT_POS_WINDOW,
        max_encoder_deviation          = DEFAULT_MAX_ENCODER_DEVIATION,
        max_velocity_deviation         = DEFAULT_MAX_VELOCITY_DEVIATION)
    set_global_parameter(dev, GP_CL_GAMMA_VMIN,                  cl_gamma_vmin)
    set_global_parameter(dev, GP_CL_GAMMA_VMAX,                  cl_gamma_vmax)
    set_global_parameter(dev, GP_CL_MAXGAMMA,                    cl_maxgamma)
    set_global_parameter(dev, GP_CL_BETA,                        cl_beta)
    set_global_parameter(dev, GP_CL_CURRENTMIN,                  cl_currentmin)
    set_global_parameter(dev, GP_CL_CURRENTMAX,                  cl_currentmax)
    set_global_parameter(dev, GP_CL_CORRECTION_VELOCITY_P,       cl_correction_velocity_p)
    set_global_parameter(dev, GP_CL_CORRECTION_VELOCITY_I,       cl_correction_velocity_i)
    set_global_parameter(dev, GP_CL_CORRECTION_VELOCITY_I_CLIP,  cl_correction_velocity_i_clip)
    set_global_parameter(dev, GP_CL_CORRECTION_VELOCITY_DV_CLK,  cl_correction_velocity_dv_clk)
    set_global_parameter(dev, GP_CL_CORRECTION_VELOCITY_DV_CLIP, cl_correction_velocity_dv_clip)
    set_global_parameter(dev, GP_CL_UPSCALE_DELAY,               cl_upscale_delay)
    set_global_parameter(dev, GP_CL_DOWNSCALE_DELAY,             cl_downscale_delay)
    set_global_parameter(dev, GP_CL_CORRECTION_POS,              cl_correction_pos)
    set_global_parameter(dev, GP_CL_MAX_CORRECTION_TOLERANCE,    cl_max_correction_tolerance)
    set_global_parameter(dev, GP_CL_STARTUP,                     cl_startup)
    set_global_parameter(dev, GP_POS_WINDOW,                     pos_window)
    set_global_parameter(dev, GP_MAX_ENCODER_DEVIATION,          max_encoder_deviation)
    set_global_parameter(dev, GP_MAX_VELOCITY_DEVIATION,         max_velocity_deviation)
    set_global_parameter(dev, GP_TMCM_COMMAND,                   2)
end
disable_closed_loop(dev)         = set_global_parameter(dev, GP_TMCM_COMMAND, 3)
enable_closed_loop(dev)          = set_global_parameter(dev, GP_TMCM_COMMAND, 4)
reference_zero(dev)              = set_global_parameter(dev, GP_TMCM_COMMAND, 5)
calibrate_axis(dev, ax::Int)     = set_global_parameter(dev, GP_TMCM_COMMAND, 6 + ax)   # ax ∈ {0,1,2} → cmd ∈ {6,7,8}
calibrate_simultaneous(dev)      = set_global_parameter(dev, GP_TMCM_COMMAND, 16)
power_off(dev)                   = set_global_parameter(dev, GP_TMCM_COMMAND, 10)
function enter_measurement_mode(dev)
    set_global_parameter(dev, GP_TMCM_COMMAND, 11)
    wait_for_idle(dev)
end
exit_measurement_mode(dev)       = set_global_parameter(dev, GP_TMCM_COMMAND, 12)
move_axis_absolute(dev, ax::Int) = set_global_parameter(dev, GP_TMCM_COMMAND, 13 + ax)  # ax ∈ {0,1,2} → cmd ∈ {13,14,15}
end_program(dev)                 = set_global_parameter(dev, GP_TMCM_COMMAND, 999)

"""
Non-destructive check: returns true if the TMCL program is currently running on the board.
Sends a Ping command (100) which the board clears to 0 without any movement or state change.
If GP10 is 0 after the wait the program responded; if still 100 nothing is running.
"""
function is_program_running(dev; wait_s::Float64 = 0.1)
    set_global_parameter(dev, GP_TMCM_COMMAND, 100)
    sleep(wait_s)
    val = get_global_parameter(dev, GP_TMCM_COMMAND)
    running = (val == 0)
    @info running ? "TMCL program is running (Ping acknowledged)." :
                    "No TMCL program running — Ping was not processed (GP10 = $val)."
    return running
end

# ============================================================
# HIGH LEVEL COMMANDS
# ============================================================
function wait_for_idle(dev; gp::Int = GP_TMCM_COMMAND, timeout_s::Float64 = 60.0)
    t0 = time()
    while true
        get_global_parameter(dev, gp) == 0 && break
        time() - t0 > timeout_s && error("Board did not become idle within $(timeout_s)s — is the TMCL program running?")
        sleep(0.1)
    end
end

function connect_board(ip::AbstractString, port::Int)
    dev = TMCLDevice("TMCM-3351", ip, port)
    @info "Connected to board at $ip:$port"
    return dev
end

# GIO opcode = 15.  Bank 1 analog inputs (TMCM-3351 manual, p.40):
#   port 8 → supply voltage [1/10 V]   port 9 → temperature [°C]
read_supply_voltage(dev) = query(dev, 15, 8, 1, 0) / 10.0   # Float64, V
read_temperature(dev)    = query(dev, 15, 9, 1, 0)           # Int, °C

function board_status(dev)
    supply_V  = read_supply_voltage(dev)
    t_C       = read_temperature(dev)
    t_K       = t_C + 273.15
    run_I     = get_axis_parameter(dev, 6, 0)
    standby_I = get_axis_parameter(dev, 7, 0)
    speed     = get_global_parameter(dev, GP_MAX_SPEED)
    accel     = get_global_parameter(dev, GP_MAX_ACCELERATION)
    decel     = get_global_parameter(dev, GP_MAX_DECELERATION)
    cur_run   = get_global_parameter(dev, GP_MAX_CURRENT)
    cur_std   = get_global_parameter(dev, GP_STANDBY_CURRENT)
    enc_res   = get_global_parameter(dev, GP_ENCODER_RESOLUTION)
    @info "Board status:"
    @info "  Supply voltage    : $(supply_V) V  (DC bus)"
    @info "  Temperature       : $(t_C) °C  /  $(t_K) K"
    @info "  Run current (AP)  : $(run_I)  (axis 0)"
    @info "  Standby cur (AP)  : $(standby_I)  (axis 0)"
    @info "Motion parameters (GP Bank 2):"
    @info "  Max speed         : $speed  usteps/s"
    @info "  Max acceleration  : $accel  usteps/s²"
    @info "  Max deceleration  : $decel  usteps/s²"
    @info "  Max current       : $cur_run  % of peak"
    @info "  Standby current   : $cur_std  % of peak"
    @info "  Encoder resolution: $enc_res  lines/rev"
    return (supply_voltage_V   = supply_V,
            temperature_C      = t_C,
            temperature_K      = t_K,
            run_current        = run_I,
            standby_current    = standby_I,
            max_speed          = speed,
            max_acceleration   = accel,
            max_deceleration   = decel,
            max_current        = cur_run,
            gp_standby_current = cur_std,
            encoder_resolution = enc_res)
end

function read_axis_status(dev)
    calib = (get_global_parameter(dev, GP_CALIB_POS_AXIS0),
             get_global_parameter(dev, GP_CALIB_POS_AXIS1),
             get_global_parameter(dev, GP_CALIB_POS_AXIS2))
    enc   = (get_axis_parameter(dev, GP_ENCODER_POS, 0),
             get_axis_parameter(dev, GP_ENCODER_POS, 1),
             get_axis_parameter(dev, GP_ENCODER_POS, 2))

    # Distance of each sled above its calibration block (calib − enc, positive = above block)
    dist_us = (calib[1] - enc[1], calib[2] - enc[2], calib[3] - enc[3])

    # Inter-axis deviations: difference in distance travelled from calibration block
    dev01_us = dist_us[1] - dist_us[2]
    dev02_us = dist_us[1] - dist_us[3]
    dev12_us = dist_us[2] - dist_us[3]

    @info "Calibration positions (usteps): axis0=$(calib[1])  axis1=$(calib[2])  axis2=$(calib[3])"
    @info "Encoder positions     (usteps): axis0=$(enc[1])  axis1=$(enc[2])  axis2=$(enc[3])"
    @info "Inter-sled deviations:"
    @info "  axis0−axis1: $(dev01_us) usteps  /  $(dev01_us / USTEPS_PER_MM) mm"
    @info "  axis0−axis2: $(dev02_us) usteps  /  $(dev02_us / USTEPS_PER_MM) mm"
    @info "  axis1−axis2: $(dev12_us) usteps  /  $(dev12_us / USTEPS_PER_MM) mm"
    @info "Distance above calibration block:"
    @info "  axis0: $(dist_us[1]) usteps  /  $(dist_us[1] / USTEPS_PER_MM) mm"
    @info "  axis1: $(dist_us[2]) usteps  /  $(dist_us[2] / USTEPS_PER_MM) mm"
    @info "  axis2: $(dist_us[3]) usteps  /  $(dist_us[3] / USTEPS_PER_MM) mm"

    return (calib_pos          = calib,
            encoder_pos        = enc,
            sled_deviation_01  = (usteps = dev01_us, mm = dev01_us / USTEPS_PER_MM),
            sled_deviation_02  = (usteps = dev02_us, mm = dev02_us / USTEPS_PER_MM),
            sled_deviation_12  = (usteps = dev12_us, mm = dev12_us / USTEPS_PER_MM),
            dist_from_calib    = (usteps = dist_us,
                                  mm     = (dist_us[1] / USTEPS_PER_MM,
                                            dist_us[2] / USTEPS_PER_MM,
                                            dist_us[3] / USTEPS_PER_MM)))
end


function read_closed_loop_status(dev)
    cl = ntuple(ax -> query(dev, 6, 129, ax - 1, 0) == 1, 3)
    for (i, enabled) in enumerate(cl)
        @info "  axis $(i-1) closed-loop: $(enabled ? "ENABLED" : "DISABLED")"
    end
    return (axis0 = cl[1], axis1 = cl[2], axis2 = cl[3])
end


"""
Move all 3 axes to `nsteps` microsteps above their respective calibration block positions.
Reads calib positions from GP 53/54/55, computes per-axis absolute targets, writes to
GP 59/60/61, then triggers StartMove (cmd 9).  Requires a prior calibrate!.
"""
function move_all_axes_to(dev, nsteps::Int, speed::Int)
    calib0 = get_global_parameter(dev, GP_CALIB_POS_AXIS0)
    calib1 = get_global_parameter(dev, GP_CALIB_POS_AXIS1)
    calib2 = get_global_parameter(dev, GP_CALIB_POS_AXIS2)
    set_global_parameter(dev, GP_MOVE_TARGET_AXIS0, calib0 - nsteps)
    set_global_parameter(dev, GP_MOVE_TARGET_AXIS1, calib1 - nsteps)
    set_global_parameter(dev, GP_MOVE_TARGET_AXIS2, calib2 - nsteps)
    set_global_parameter(dev, GP_MAX_SPEED,         speed)
    set_global_parameter(dev, GP_TMCM_COMMAND,      9)
end

"""
Move a single axis to an absolute encoder position.
ax ∈ {0,1,2}, position in encoder microsteps.
"""
function move_absolute_axis_to(dev, ax::Int, position::Int, speed::Int)
    set_global_parameter(dev, GP_TARGET_POS, position)
    set_global_parameter(dev, GP_MAX_SPEED,  speed)
    move_axis_absolute(dev, ax)   # GP_TMCM_COMMAND = 13/14/15
end

"""
Move a single axis to `nsteps` microsteps above its calibration block position.
Reads CALIB_POS_AXISn from GP 53/54/55, computes absolute target, writes to
GP 59/60/61, then triggers MoveAxis0/1/2AboveCalib (cmd 17/18/19).
ax ∈ {0,1,2}.  Requires a prior calibrate!.
"""
function move_axis_above_calib(dev, ax::Int, nsteps::Int, speed::Int)
    gp_calib  = (GP_CALIB_POS_AXIS0,   GP_CALIB_POS_AXIS1,   GP_CALIB_POS_AXIS2  )[ax + 1]
    gp_target = (GP_MOVE_TARGET_AXIS0, GP_MOVE_TARGET_AXIS1, GP_MOVE_TARGET_AXIS2)[ax + 1]
    calib = get_global_parameter(dev, gp_calib)
    set_global_parameter(dev, gp_target, calib - nsteps)
    set_global_parameter(dev, GP_MAX_SPEED, speed)
    set_global_parameter(dev, GP_TMCM_COMMAND, 17 + ax)   # 17/18/19 → MoveAxis0/1/2AboveCalib
end

"""
Move all 3 axes to `distance_cm` centimetres above their respective calibration
block positions.  `speed_cm_s` is the motion speed in cm/s.
Converts to microsteps internally using USTEPS_PER_CM (102,400 usteps/cm).
"""
function move_all_axes_to_cm(dev, distance_cm::Real, speed_cm_s::Real)
    move_all_axes_to(dev, round(Int, distance_cm * USTEPS_PER_CM),
                          round(Int, speed_cm_s  * USTEPS_PER_CM))
end

"""
Move a single axis to `distance_cm` centimetres above its calibration block position.
`speed_cm_s` is the motion speed in cm/s.  ax ∈ {0,1,2}.
Converts to microsteps internally using USTEPS_PER_CM (102,400 usteps/cm).
"""
function move_axis_above_calib_cm(dev, ax::Int, distance_cm::Real, speed_cm_s::Real)
    move_axis_above_calib(dev, ax, round(Int, distance_cm * USTEPS_PER_CM),
                                   round(Int, speed_cm_s  * USTEPS_PER_CM))
end


# ─────────────────────────────────────────────────────────────────────────────
# startup!
# Must be called once per power-cycle, before calibration.
# Sleds must be physically above the calibration blocks before calling this.
# ─────────────────────────────────────────────────────────────────────────────
function startup!(dev)
    @info "PowerOn — set motion params, sync encoder/actual/target"
    power_on(dev);             wait_for_idle(dev)

    @info "StartInit — load closed-loop PID parameters"
    start_init(dev);           wait_for_idle(dev)

    @info "DisableClosedLoop"
    disable_closed_loop(dev);  wait_for_idle(dev)

    @info "EnableClosedLoop — clean CL init before any move"
    enable_closed_loop(dev);   wait_for_idle(dev)

    @info "Startup complete."
end

# ─────────────────────────────────────────────────────────────────────────────
# startup_loaded!
# Same sequence as startup! but with parameters tuned for the ~20 kg lead block.
# Use instead of startup! whenever the block is on the platform.
# The lead screws are self-locking so no standby_current change is needed —
# the platform holds position without motor power regardless.
# ─────────────────────────────────────────────────────────────────────────────
function startup_loaded!(dev)
    @info "PowerOn (loaded) — higher current, slower ramp for 20 kg block"
    power_on(dev;
        max_current      = LOADED_MAX_CURRENT,
        max_speed        = LOADED_MAX_SPEED,
        max_acceleration = LOADED_MAX_ACCELERATION,
        max_deceleration = LOADED_MAX_DECELERATION)
    wait_for_idle(dev)

    @info "StartInit (loaded) — looser stall-detection tolerances"
    start_init(dev;
        max_encoder_deviation  = LOADED_MAX_ENCODER_DEVIATION,
        max_velocity_deviation = LOADED_MAX_VELOCITY_DEVIATION)
    wait_for_idle(dev)

    @info "DisableClosedLoop"
    disable_closed_loop(dev);  wait_for_idle(dev)

    @info "EnableClosedLoop — clean CL init before any move"
    enable_closed_loop(dev);   wait_for_idle(dev)

    @info "Startup (loaded) complete."
end

# ─────────────────────────────────────────────────────────────────────────────
#This function should only be run after unplugging the board otherwise the 0 value is remembered
# ─────────────────────────────────────────────────────────────────────────────
function RefZero_run_only_once_after_unplugging_board!(dev)
    @info "ReferenceZero — set current sled positions as encoder origin"
    reference_zero(dev);       wait_for_idle(dev)
end

# ─────────────────────────────────────────────────────────────────────────────
# calibrate!
# Descend all 3 axes simultaneously to the calibration blocks and save positions.
# Do not call reference_zero again after this.
# ─────────────────────────────────────────────────────────────────────────────
function calibrate!(dev)
    @info "SimultaneousCalibration — all 3 axes descend, stall, positions saved at GP 53/54/55"
    calibrate_simultaneous(dev); wait_for_idle(dev)
    # Persist calibration positions to EEPROM (STGP opcode 11) so they survive power cycles.
    # Bank 2 variables 0–55 are EEPROM-restorable; GP 53/54/55 are within that range.
    query(dev, 11, GP_CALIB_POS_AXIS0, GP_BANK, 0)
    query(dev, 11, GP_CALIB_POS_AXIS1, GP_BANK, 0)
    query(dev, 11, GP_CALIB_POS_AXIS2, GP_BANK, 0)
    @info "Calibration complete. Positions saved to EEPROM."
end

# ─────────────────────────────────────────────────────────────────────────────
# end_measurement!
# ─────────────────────────────────────────────────────────────────────────────
function end_measurement!(dev;
        max_current     = DEFAULT_MAX_CURRENT,
        standby_current = DEFAULT_STANDBY_CURRENT)
    # SAP (direct axis parameter write) works reliably with CL active.
    # AAP/GGP inside ExitMeasurementMode does not — CL interferes.
    for ax in 0:2
        set_axis_parameter(dev, 6, ax, max_current)
        set_axis_parameter(dev, 7, ax, standby_current)
    end
    @info "ExitMeasurementMode — restore currents (run=$(max_current), standby=$(standby_current))"
    exit_measurement_mode(dev); wait_for_idle(dev)
end
# ─────────────────────────────────────────────────────────────────────────────
# shutdown!
# ─────────────────────────────────────────────────────────────────────────────
function shutdown!(dev)
    @info "PowerOff"
    power_off(dev); wait_for_idle(dev)
    @info "Board powered off."
end

end # module
