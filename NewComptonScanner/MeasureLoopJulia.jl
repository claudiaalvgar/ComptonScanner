measurement_points = [10000, 20000, 30000]

function wait_for_idle(port)
    while get_global_parameter(port, 10) != 0
        sleep(0.1)
    end
end

# ===== Boot =====
set_global_parameter(port, 10, 4)
wait_for_idle(port)

set_global_parameter(port, 10, 3)
wait_for_idle(port)

set_global_parameter(port, 10, 2)
wait_for_idle(port)

# ===== Loop =====
for target in measurement_points

    println("Moving to $target")

    set_global_parameter(port, 0, target)
    set_global_parameter(port, 1, 1000)
    set_global_parameter(port, 10, 1)
    wait_for_idle(port)

    println("Power OFF for measurement")
    set_global_parameter(port, 10, 5)
    wait_for_idle(port)

    # ---- YOUR MEASUREMENT HERE ----
    sleep(2)

    println("Power ON again")
    set_global_parameter(port, 10, 4)
    wait_for_idle(port)
end

println("All measurements done!")