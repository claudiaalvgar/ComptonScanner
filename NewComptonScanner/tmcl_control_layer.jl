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
       move_absolute_axis_to,
       end_program,
       startup!,
       calibrate!,
       move_and_measure!,
       end_measurement!,
       shutdown!

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
enter_measurement_mode(dev)      = set_global_parameter(dev, GP_TMCM_COMMAND, 11)
exit_measurement_mode(dev)       = set_global_parameter(dev, GP_TMCM_COMMAND, 12)
move_axis_absolute(dev, ax::Int) = set_global_parameter(dev, GP_TMCM_COMMAND, 13 + ax)  # ax ∈ {0,1,2} → cmd ∈ {13,14,15}
end_program(dev)                 = set_global_parameter(dev, GP_TMCM_COMMAND, 999)

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
    supply_V  = read_supply_voltage(dev)        # DC bus voltage (GIO 8, Bank 1)
    t_C       = read_temperature(dev)
    t_K       = t_C + 273.15
    run_I     = get_axis_parameter(dev, 6, 0)   # AP 6: run current (axis 0, % of max)
    standby_I = get_axis_parameter(dev, 7, 0)   # AP 7: standby current (axis 0, % of max)
    @info "Board status:"
    @info "  Supply voltage : $(supply_V) V  (DC bus)"
    @info "  Temperature    : $(t_C) °C  /  $(t_K) K"
    @info "  Run current    : $(run_I)  (AP 6, axis 0)"
    @info "  Standby current: $(standby_I)  (AP 7, axis 0)"
    return (supply_voltage_V = supply_V,
            temperature_C    = t_C,
            temperature_K    = t_K,
            run_current      = run_I,
            standby_current  = standby_I)
end

function read_axis_status(dev)
    calib = (get_global_parameter(dev, GP_CALIB_POS_AXIS0),
             get_global_parameter(dev, GP_CALIB_POS_AXIS1),
             get_global_parameter(dev, GP_CALIB_POS_AXIS2))
    enc   = (get_axis_parameter(dev, GP_ENCODER_POS, 0),
             get_axis_parameter(dev, GP_ENCODER_POS, 1),
             get_axis_parameter(dev, GP_ENCODER_POS, 2))
    @info "Calibration positions (usteps): axis0=$(calib[1])  axis1=$(calib[2])  axis2=$(calib[3])"
    @info "Encoder positions     (usteps): axis0=$(enc[1])  axis1=$(enc[2])  axis2=$(enc[3])"
    return (calib_pos = calib, encoder_pos = enc)
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

    @info "ReferenceZero — set current sled positions as encoder origin"
    reference_zero(dev);       wait_for_idle(dev)

    @info "Startup complete."
end

# ─────────────────────────────────────────────────────────────────────────────
# calibrate!
# Descend all 3 axes simultaneously to the calibration blocks and save positions.
# Do not call reference_zero again after this.
# ─────────────────────────────────────────────────────────────────────────────
function calibrate!(dev)
    @info "SimultaneousCalibration — all 3 axes descend, stall, positions saved at GP 53/54/55"
    calibrate_simultaneous(dev); wait_for_idle(dev)
    @info "Calibration complete."
end

# ─────────────────────────────────────────────────────────────────────────────
# move_and_measure! and exit_measurement_mode!
# ─────────────────────────────────────────────────────────────────────────────
function move_and_measure!(dev, nsteps_to_move::Int, speed::Int)
    @info "Moving to scan position: $nsteps_to_move usteps above block"
    move_all_axes_to(dev, nsteps_to_move, speed); wait_for_idle(dev)

    @info "EnterMeasurementMode — stop motors, zero currents"
    enter_measurement_mode(dev); wait_for_idle(dev)

    @info "At measurement position."
end

function end_measurement!(dev;
        max_current     = DEFAULT_MAX_CURRENT,
        standby_current = DEFAULT_STANDBY_CURRENT)
    # Write GP6/7 explicitly so the board has the correct values to restore,
    # regardless of whether power_on was called in this session.
    set_global_parameter(dev, GP_MAX_CURRENT,     max_current)
    set_global_parameter(dev, GP_STANDBY_CURRENT, standby_current)
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
