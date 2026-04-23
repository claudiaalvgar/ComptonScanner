# 1. Boot up sequence (run once at the start of the day)
set_global_parameter(port, 10, 4) # Power ON
wait_for_idle(port)               # Custom function that loops until GP 10 == 0
set_global_parameter(port, 10, 3) # Initialize Closed-Loop Commutation
wait_for_idle(port)
set_global_parameter(port, 10, 2) # Home the system to the bottom limit
wait_for_idle(port)

# 2. The Measurement Loop
for target in measurement_points
    # Move
    set_global_parameter(port, 0, target)  # Set Position
    set_global_parameter(port, 1, 1000)    # Set Speed
    set_global_parameter(port, 10, 1)      # Execute Move
    wait_for_idle(port)

    # Dark Mode
    set_global_parameter(port, 10, 5)      # Power OFF
    wait_for_idle(port)

    # ... Take Physics Measurements ...

    # Wake Up
    set_global_parameter(port, 10, 4)      # Power ON (automatically handles the 50ms delay)
    wait_for_idle(port)
end