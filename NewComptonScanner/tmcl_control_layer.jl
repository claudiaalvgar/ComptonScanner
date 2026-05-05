module TMCLControlLayer

export TMCLDevice,
       set_global_parameter,
       get_global_parameter,
       wait_for_idle,
       power_on,
       power_off,
       move,
       home,
       init_system,
       move_to

using TrinamicMotionControl

# ============================================================
# IMPORTANT CONSTANT
# ============================================================
#=
field	value	meaning
9	SGP	"Set Global Parameter"
gp	e.g. 10	GP index
GP_BANK	2	Bank 2
value	e.g. 4	command

Julia	TMCL
move()	GP10 = 1
home()	GP10 = 2
init_system()	GP10 = 3
power_off()	GP10 = 5

Bank	Usage
0	default / firmware
1	user parameters
2	custom control logic (like your state machine)
=#
const GP_BANK = 2   # ← MUST match your TMCL script (you used Bank 2!)

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

# ============================================================
# STATE MACHINE HELPERS
# ============================================================

function wait_for_idle(dev; gp::Int = 10)
    while true
        state = get_global_parameter(dev, gp)
        state == 0 && break
        sleep(0.1)
    end
end

power_on(dev)   = set_global_parameter(dev, 10, 4)
power_off(dev)  = set_global_parameter(dev, 10, 5)
move(dev)       = set_global_parameter(dev, 10, 1)
home(dev)       = set_global_parameter(dev, 10, 2)
init_system(dev)= set_global_parameter(dev, 10, 3)

# ============================================================
# HIGH LEVEL COMMAND
# ============================================================

function move_to(dev, position::Int, speed::Int)
    set_global_parameter(dev, 0, position)   # GP0 = target position
    set_global_parameter(dev, 1, speed)      # GP1 = speed
    move(dev)                                # GP10 = 1
end

end # module
