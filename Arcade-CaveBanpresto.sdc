derive_pll_clocks
derive_clock_uncertainty

# The Cave core uses the 96 MHz and 32 MHz outputs of the main PLL as separate
# handoff domains. CPU-side ROM/device requests cross through freezer/FIFO
# bridges, so timing the two PLL outputs as ordinary single-cycle related clocks
# creates huge false setup failures on the bridge data paths.
set_false_path \
  -from [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
  -to   [get_clocks {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]

set_false_path \
  -from [get_clocks {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] \
  -to   [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]

# Static game selector crossing into the CPU clock domain. The 4-bit payload is
# only sampled after the synchronized load toggle reaches cpuClock.
set_false_path \
  -from [get_registers {*|Cave:cave|gameIndexReg*}] \
  -to [get_registers {*|Cave:cave|gameIndexCpuReg*}]

set_false_path \
  -from [get_registers {*|Cave:cave|gameIndexCpuLoadToggle*}] \
  -to [get_registers {*|Cave:cave|gameIndexCpuToggleSync0*}]

# Define clock group for pll_video
set_clock_groups -exclusive \
  -group [get_clocks {emu|pll_video|pll_video_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
