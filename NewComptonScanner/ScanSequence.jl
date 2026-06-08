# ScanSequence.jl
# Complete startup + calibration + measurement scan sequence for the
# TMCM-3351 controlled by TMCMCode_newversion.tmc.

#Function	                                What it does
#startup!(dev)	                                PowerOn → StartInit → DisableCL → EnableCL → ReferenceZero
#calibrate!(dev)	                        SimultaneousCalibration
#scan_sequence!(dev, points; speed, measure)	Move → EnterMeasurement → measure() → ExitMeasurement loop
#shutdown!(dev)	                                PowerOff

using TrinamicMotionControl
include("tmcl_control_layer.jl")
using .TMCLControlLayer

# ── board connection ──────────────────────────────────────────────────────────
const BOARD_IP   = "192.168.0.2"   # adjust to your board IP
const BOARD_PORT = 4016            # adjust to your board port

# ── scan configuration ────────────────────────────────────────────────────────
# Offsets above the copper block in microsteps (positive = upward).
# 51,200 usteps = 5 mm = 1 motor revolution.
const DEFAULT_SCAN_POINTS = [500_000, 400_000, 300_000]  # example heights
const DEFAULT_SPEED        = 51_200   # usteps/s

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
# scan_sequence!
# Runs the full measurement loop over a list of offsets (microsteps above block).
# Calls the user-supplied measure() function at each position.
# ─────────────────────────────────────────────────────────────────────────────
function scan_sequence!(dev, scan_points; speed = DEFAULT_SPEED, measure = () -> sleep(5))
    @info "Moving to first scan position: $(first(scan_points)) usteps above block"
    move_to(dev, first(scan_points), speed); wait_for_idle(dev)

    for (i, offset) in enumerate(scan_points)
        @info "── Position $i/$(length(scan_points)): $offset usteps above block ──"

        move_to(dev, offset, speed); wait_for_idle(dev)

        @info "EnterMeasurementMode — stop motors, zero currents"
        enter_measurement_mode(dev); wait_for_idle(dev)

        @info "Measuring…"
        measure()

        @info "ExitMeasurementMode — restore currents"
        exit_measurement_mode(dev); wait_for_idle(dev)
    end

    @info "Scan complete."
end

# ─────────────────────────────────────────────────────────────────────────────
# shutdown!
# ─────────────────────────────────────────────────────────────────────────────
function shutdown!(dev)
    @info "PowerOff"
    power_off(dev); wait_for_idle(dev)
    @info "Board powered off."
end

# ─────────────────────────────────────────────────────────────────────────────
# run_full_scan
# Top-level entry point: connects, runs startup + calibration + scan + shutdown.
# Replace the `measure` keyword argument with your actual DAQ call.
# ─────────────────────────────────────────────────────────────────────────────
function run_full_scan(;
    ip          = BOARD_IP,
    port        = BOARD_PORT,
    scan_points = DEFAULT_SCAN_POINTS,
    speed       = DEFAULT_SPEED,
    measure     = () -> sleep(5),   # replace with your HPGe acquisition call
)
    dev = TMCLDevice("TMCM-3351", ip, port)

    try
        startup!(dev)
        calibrate!(dev)
        scan_sequence!(dev, scan_points; speed, measure)
    catch e
        @error "Scan aborted" exception = e
        rethrow()
    finally
        shutdown!(dev)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Run when executed directly: julia ScanSequence.jl
# ─────────────────────────────────────────────────────────────────────────────
if abspath(PROGRAM_FILE) == @__FILE__
    run_full_scan()
end
