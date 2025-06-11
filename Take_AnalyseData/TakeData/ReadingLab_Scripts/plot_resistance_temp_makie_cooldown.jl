using CSV
using DataFrames
using CairoMakie
using Dates
# using TimeZones

# --- Step 1: Read the CSV with headers

filename = "resistance_log_20250513T125707Z_cooldown.csv"  # Update this with your actual path
df = CSV.read(filename, DataFrame)

# --- Step 2: Print column names to verify
println("Column names: ", names(df))

#Titles
col1_title = "timestamp"
col2_title = "resistance_seg4"
col3_title = "resistance_reference"
col4_title = "pt100-1"
col5_title = "pt100-2"


col1_sym = Symbol(col1_title)
col2_sym = Symbol(col2_title)
col3_sym = Symbol(col3_title)
col4_sym = Symbol(col4_title)
col5_sym = Symbol(col5_title)

col1 = df[!, col1_sym]
col2 = df[!, col2_sym]
col3 = df[!, col3_sym]
col4 = df[!, col4_sym]
col5 = df[!, col5_sym]


# --- Step 2.5: Replace Overloads by NaN
col2[findall(col2 .> 1e36)] .= NaN
col3[findall(col3 .> 1e36)] .= NaN


col1_dt = DateTime.(col1, "yyyymmddTHHMMSSZ")

ref = DateTime("20250513T125715Z", "yyyymmddTHHMMSSZ")

minutes = [(dt - ref).value ÷ 60_000 for dt in col1_dt]

#println(minutes)

# --- Plot with Makie
f = Figure()


# Primary axis (left) for resistance
ax_left = Axis(f[1, 1], yscale = Makie.log10, xlabel = "Time [min]", ylabel = "Resistance [Ω]", title = "HPGe Cool Down")
lines!(ax_left, minutes, col2, label = "Seg4", color = :blue)
lines!(ax_left, minutes, col3, label = "Ref", color = :green)

# Secondary axis (right) for temperature
ax_right = Axis(f[1, 1], yaxisposition = :right, ylabel = "Temperature [K]", xticklabelsvisible = false, title = "HPGe Cool Down")
lines!(ax_right, minutes, col4, label = "PT100-1", color = :red)
lines!(ax_right, minutes, col5, label = "PT100-2", color = :orange)

# Save current y-limits of ax_right (or use `nothing` to auto-scale)
old_y = ax_right.limits[][2]

# Set new x-limits while preserving y-limits
ax_right.limits[] = ((0, 900), (0,300))
ax_left.limits[] = ((0, 900), old_y)

axislegend(ax_left; position = :lc)
axislegend(ax_right; position = :rt)

f

save("CombinedResult_CoolDown.png",f)