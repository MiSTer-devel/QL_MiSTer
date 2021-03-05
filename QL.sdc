derive_pll_clocks
derive_clock_uncertainty

set_multicycle_path -from {emu|fx68k|*} -setup 2
set_multicycle_path -from {emu|fx68k|*} -hold 1

set_multicycle_path -to {emu|video_mixer|*} -setup 2
set_multicycle_path -to {emu|video_mixer|*} -hold 1
