using TrinamicMotionControl
include("tmcl_control_layer.jl")
using .TMCLControlLayer

#(USB serial device name assigned by the system when you plug in the motor controller, the speed of communication between your Mac and the motor controller)
port = TMCLPort("/dev/cu.usbserial-XXXX", 115200)
#=
GP10 = state machine register
GP10 value	Meaning
0	idle / done
1	move
2	home
3	init
4	power on
5	power off
99	error
=#
# ===== Helper function =====
function wait_for_idle(port)
    while true
        state = get_global_parameter(port, 10)
        if state == 0
            break
        end
        sleep(0.1)
    end
end

# ===== Main control =====
target_position = 100000   # change this
speed = 1000               # change this

# Power ON
set_global_parameter(port, 10, 4)
wait_for_idle(port)

# Init
set_global_parameter(port, 10, 3)
wait_for_idle(port)

# Home
set_global_parameter(port, 10, 2)
wait_for_idle(port)

# Move
set_global_parameter(port, 0, target_position)
set_global_parameter(port, 1, speed)
set_global_parameter(port, 10, 1)
wait_for_idle(port)

println("Move complete!")
