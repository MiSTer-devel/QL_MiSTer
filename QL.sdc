derive_pll_clocks
derive_clock_uncertainty

set_multicycle_path -from [get_clocks {*|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -to [get_clocks {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -setup 2
set_multicycle_path -from [get_clocks {*|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -to [get_clocks {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -hold 1

set_multicycle_path -from [get_clocks {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -to [get_clocks {*|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -start -setup 2
set_multicycle_path -from [get_clocks {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -to [get_clocks {*|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -start -hold 1

set_multicycle_path -from {emu|tg68k|*} -setup 2
set_multicycle_path -from {emu|tg68k|*} -hold 1

set_multicycle_path -to {emu|video_mixer|*} -setup 2
set_multicycle_path -to {emu|video_mixer|*} -hold 1
