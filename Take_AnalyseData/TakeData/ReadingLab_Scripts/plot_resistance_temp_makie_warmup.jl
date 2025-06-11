using CSV
using DataFrames
using CairoMakie
using Dates


# --- Step 1: Read the CSV with headers

filename = "resistance_log_20250514T165420Z_warmup.csv"  # Update this with your actual path
df = CSV.read(filename, DataFrame)

# --- Step 2: Print column names to verify
println("Column names: ", names(df))


#Titles
#Column names: ["t1", "resistance_seg4", "range_seg4", "t2", "resistance_reference", "range_reference", "t3", "pt100-1", "pt100-2", "t4"]

col_title = String[]
col_sym = Symbol[]


col = Vector{AbstractVector}(undef, length(names(df)))  # Vector to store columns


for i in 1:length(names(df))
    push!(col_title, String(names(df)[i]))
    println(col_title[i])

    push!(col_sym, Symbol(col_title[i]))

    #It extracts a column from the DataFrame df using the symbol col1_sym as the column name and returns a direct reference (not a copy) to that column.
    col[i] = df[!, col_sym[i]]
    #println(col[i])
    #println(" next column ")
end


# --- Step 2.5: Replace Overloads by NaN
col[2][findall(col[2] .> 1e36)] .= NaN
col[5][findall(col[5] .> 1e36)] .= NaN



# Axis array for times

col_dt1 = DateTime.(col[1], "yyyymmddTHHMMSSZ") #col_dt1 - col[2] : t1 for resistance_seg4 (col[3] range_seg4) 
col_dt2 = DateTime.(col[4], "yyyymmddTHHMMSSZ") #col_dt2 - col[5] : t2 for resistance_reference (col[6] range_reference)
col_dt3 = DateTime.(col[7], "yyyymmddTHHMMSSZ") #col_dt3 - col[8] and col[9] : t3 for pt100-1 and pt100-2
col_dt4 = DateTime.(col[10], "yyyymmddTHHMMSSZ") #col_dt4 : end time


ref = DateTime("20250514T165427Z", "yyyymmddTHHMMSSZ")

minutes_t1 = [(dt - ref).value ÷ 60_000 for dt in col_dt1]
minutes_t2 = [(dt - ref).value ÷ 60_000 for dt in col_dt2]
minutes_t3 = [(dt - ref).value ÷ 60_000 for dt in col_dt3]
minutes_t4 = [(dt - ref).value ÷ 60_000 for dt in col_dt4]

# --- Plot with Makie--- Resistance + Temperature
f = Figure()



#PLOT RESISTANCE AND TEMPERATURE AGAINST TIME

#=
# Primary axis (left) for resistance
ax_left = Axis(f[1, 1], yscale = Makie.log10, xlabel = "Time [min]", ylabel = "Resistance [Ω]", title = "HPGe Warm Up")
lines!(ax_left, minutes_t1, col[2], label = "Seg4", color = :blue)
lines!(ax_left, minutes_t2, col[5], label = "Ref", color = :green)

# Secondary axis (right) for temperature
ax_right = Axis(f[1, 1], yaxisposition = :right, ylabel = "Temperature [K]", xticklabelsvisible = false, title = "HPGe Warm Up")
lines!(ax_right, minutes_t3, col[8], label = "PT100-1", color = :red)
lines!(ax_right, minutes_t3, col[9], label = "PT100-2", color = :orange)

# Save current y-limits of ax_right (or use `nothing` to auto-scale)
old_y = ax_right.limits[][2]

# Set new x-limits while preserving y-limits
ax_right.limits[] = ((0, 900), (0,300))
ax_left.limits[] = ((0, 900), old_y)


axislegend(ax_left; position = :lb)
axislegend(ax_right; position = :rc)

f

#save("CombinedResult_WarmUp.png",f)
=#

#PLOT RESISTANCE RANGE AGAINST TIME

#=
ax_left = Axis(f[1, 1], xlabel = "Time [min]", ylabel = "Resistance range", title = "HPGe Warm Up")
lines!(ax_left, minutes_t1, col[3], label = "Seg4", color = :blue)
lines!(ax_left, minutes_t2, col[6], label = "Ref", color = :green)

#scatter!(ax_left, minutes_t1, col[3]; color = :blue, marker = :circle, markersize = 6, label = "Seg4")
#scatter!(ax_left, minutes_t2, col[6]; color = :green, marker = :circle, markersize = 6, label = "Ref")

text!(ax_left, "Ranges\n 0 = 200 Ω\n 1 = 2 kΩ\n 2 = 20 kΩ\n 3 = 200 kΩ\n 4 = 1 MΩ\n 5 = 10 MΩ\n 6 = 100 MΩ\n", position = (600, 6), align = (:left, :top), color = :black)

old_y = ax_left.limits[][2]
# Set new x-limits while preserving y-limits
ax_left.limits[] = ((0, 900), old_y)


axislegend(ax_left; position = :lb)

f

#save("ResistanceRanges_WarmUp.png",f)
=#


#PLOT DELTA TIME FOR RESISTANCE SEG 4 and RESISTANCE REFFERENCE

#delta t
n = min(length(minutes_t2), length(minutes_t1))
data = minutes_t2[1:n] .- minutes_t1[1:n]

n_ = min(length(minutes_t3), length(minutes_t2))
data_ = minutes_t3[1:n_] .- minutes_t2[1:n_]

for (i, val) in enumerate(data)
    println("Index $i: $val")
end


f = Figure()

ax_left = Axis(f[1, 1], xlabel = L"\Delta t\ \mathrm{[min]}", ylabel = "Resistance range", title = "HPGe Warm Up")
#scatter!(ax_left, data, col[3], label = "Seg4", color = :blue)
#lines!(ax_left, data, col[3], color = :blue)

scatter!(ax_left, data_, col[6], label = "Ref", color = :green)
lines!(ax_left, data_, col[6], color = :green)

axislegend(ax_left; position = :rt)

#save("Deltat_RangeResSeg4.png",f)
#save("Deltat_RangeResRef.png",f)

#ax = Axis(f[1, 1], xlabel = L"\Delta t\ \mathrm{for\ Seg4\ [min]}", ylabel = "N measurements", title = "")
# Add filled histogram
#hist!(ax, data; bins = 40, color = :steelblue, strokewidth = 0)

f

#save("Deltat_ResSeg4.png",f)


#=

f = Figure()
ax = Axis(f[1, 1], xlabel = L"\Delta t\ \mathrm{for\ Ref\ [min]}", ylabel = "N measurements", title = "")

# Add filled histogram
hist!(ax, data_; bins = 40, color = :steelblue, strokewidth = 0)

f

#save("Deltat_ResRef.png",f)
=#