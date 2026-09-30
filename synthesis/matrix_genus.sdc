# =============================================================
# matmul4x4_accel.sdc
# SDC constraints for matmul4x4_accel (Config F)
# Target: SKY130HD (sky130_fd_sc_hd)
# Clock: 100 MHz (10 ns period) — matches testbench clock gen
# =============================================================

# -----------------------------------------------------------
# Clock definition
# -----------------------------------------------------------
create_clock -name clk -period 10.0 [get_ports clk]

# Clock uncertainty (setup/hold margin for jitter + skew)
set_clock_uncertainty -setup 0.15 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]

# Clock transition (rise/fall time budget for the clock tree)
set_clock_transition 0.15 [get_clocks clk]

# -----------------------------------------------------------
# Input delays (all inputs are synchronous, sampled on posedge clk)
# 4.0 ns = 40% of the 10 ns period
# -----------------------------------------------------------
set_input_delay -clock clk 4.0 [get_ports rst_n]
set_input_delay -clock clk 4.0 [get_ports start]
set_input_delay -clock clk 4.0 [get_ports wr_en]
set_input_delay -clock clk 4.0 [get_ports {wr_data[*]}]
set_input_delay -clock clk 4.0 [get_ports rd_en]

# -----------------------------------------------------------
# Output delays (all outputs assumed sampled by a downstream
# synchronous block)
# -----------------------------------------------------------
set_output_delay -clock clk 4.0 [get_ports ready]
set_output_delay -clock clk 4.0 [get_ports done]
set_output_delay -clock clk 4.0 [get_ports {c_data[*]}]

# -----------------------------------------------------------
# Driving cell / load (optional but recommended for realistic
# extraction — adjust to your actual pad/fanout assumptions)
# -----------------------------------------------------------
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 \
    [all_inputs]
set_load 0.05 [all_outputs]

# -----------------------------------------------------------
# No CDC in this revision (single clock domain, per RTL header) --
# so no false paths / multicycle paths are required.
# -----------------------------------------------------------
