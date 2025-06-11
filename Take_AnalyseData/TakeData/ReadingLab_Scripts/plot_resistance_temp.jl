using CSV
using DataFrames
using Plots

# --- Step 1: Read the CSV with headers

filename = "resistance_log_20250513T125707Z.csv"  # Update this with your actual path
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
#col2[findall(col2 .> 1e36)] .= NaN
#col3[findall(col3 .> 1e36)] .= NaN

# --- Step 3: Plot Column2 vs Column4 as a scatter plot
p = scatter(col4, col3,
    xlabel = col4_title,
    ylabel = col3_title,
    title = " ",
    legend = false,
    markerstrokewidth = 0.5,
    markersize = 6)

savefig(p,"ResistanceRefference_temperature.png")