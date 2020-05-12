//============================================================================
//  Sinclair QL
//
//  Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output  [1:0] VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;

assign LED_USER  = mdv_led | ioctl_download | sd_act;
assign LED_DISK  = {1'b1, status[0]};
assign LED_POWER = 0;
assign BUTTONS   = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 

`include "build_id.v" 
parameter CONF_STR = {
	"QL;;",
	"-;",
	"F,MDV;",
	"O2,MDV direction,normal,reverse;",
	"-;",
	"O3,Video mode,PAL,NTSC;",
	"O1,Aspect ratio,4:3,16:9;",
	"O9A,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"-;",
	"O78,CPU speed,Normal,x2,x4;",
	"O45,RAM,128k,640k,896k;",
	"T6,Reset & unload MDV;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_11m;
wire clk_sys;
wire pll_locked;

wire ce_bus_p  = duty_cycle & ce_p;
wire ce_bus_n  = duty_cycle & ce_n;
wire cpu_cycle = duty_cycle & sub_cycle;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_11m),
	.locked(pll_locked)
);

reg ce_p, ce_n;
reg ce_vid;
reg ce_sd;
reg duty_cycle;
reg sub_cycle;
reg ce_131k;
always @(negedge clk_sys) begin
	reg [4:0] div;
	reg [9:0] div131k;
	
	div131k<= div131k + 1'd1;
	if(div131k == 640) div131k <= 0;
	ce_131k <= !div131k;
	
	div    <= div + 1'd1;

	ce_p   <= (div[2:0] == 0);
	ce_n   <= (div[2:0] == 4);

	ce_vid <= !div[2:0];
	ce_sd  <= !div[1:0];

	if(!div[2:0]) begin
		case(status[8:7])
			0: duty_cycle <= !div[4:3];
			1: duty_cycle <= !div[3];
			2,3: duty_cycle <= 1;
		endcase
		
		if(!div[4:3]) sub_cycle <= ~sub_cycle || status[8:7];
	end
end

/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [15:0] joystick_0, joystick_1;
wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout = {ioctl_data[7:0], ioctl_data[15:8]};
wire [15:0] ioctl_data;
reg         ioctl_wait = 0;

wire [24:0] ps2_mouse;
wire [10:0] ps2_key;
wire [32:0] TIMESTAMP;

wire        forced_scandoubler;
wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	
	.TIMESTAMP(TIMESTAMP),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);

/////////////////  SD  ////////////////////////////

wire qlsd_rd = cpu_rom && (cpu_addr[15:0] == 16'hfee4);  // only one register actually returns data
wire [7:0] qlsd_dout;

qlromext qlromext
(
	.clk		( clk_sys    		),

	.cen     ( ce_bus_n        ),
	.ce_sd	( ce_sd    			),

	.romoel  ( !(cpu_rom && cpu_cycle) ),
	.a       ( cpu_addr[15:0]	),
	.d       ( qlsd_dout       ),
	.sd_do   ( SD_MISO         ),
	.sd_cs1l ( SD_CS           ),
	.sd_clk  ( SD_SCK          ),
	.sd_di   ( SD_MOSI         ),
	.io2     ( 1'b0            )
); 

/////////////////  RESET  /////////////////////////

reg [11:0] reset_cnt;
wire reset = (reset_cnt != 0);
always @(posedge clk_sys) begin
	if(RESET || buttons[1] || status[0] || !pll_locked || rom_download)
		reset_cnt <= 12'hfff;
	else if(ce_bus_p && reset_cnt != 0)
		reset_cnt <= reset_cnt - 1'd1;
end

/////////////////  SDRAM  /////////////////////////

wire rom_download = ioctl_download && !ioctl_index;

wire [23:0] sdram_addr = { 5'b00000, cpu_addr[19:1]};
wire [15:0] sdram_din  = cpu_dout;
wire        sdram_wr   = cpu_cycle & cpu_wr & cpu_ram;
wire        sdram_oe   = cpu_cycle & cpu_rd & cpu_ram;
wire  [1:0] sdram_ds   = ~cpu_ds;
wire [15:0] sdram_dout;

assign SDRAM_CKE = 1;
sdram sdram
(
	.*,

   // system interface
   .clk    ( clk_sys     ),
   .sync   ( ce_p        ),
   .init   ( !pll_locked ),

   // cpu interface
   .din    ( sdram_din   ),
   .addr   ( sdram_addr  ),
   .we     ( sdram_wr    ),
   .oe     ( sdram_oe    ),
   .ds     ( sdram_ds    ),
   .dout   ( sdram_dout  )
);

wire [15:0] rom_dout;
dpram #(15) rom
(
	.wrclock(clk_sys),
	.wraddress(ioctl_addr[15:1]),
	.wren(ioctl_wr && !ioctl_index),
	.byteena_a(2'b11),
	.data(ioctl_dout),

	.rdclock(clk_sys),
	.rdaddress(cpu_addr[15:1]),
	.q(rom_dout)
);

wire [15:0] vram_dout;
dpram #(15) vram
(
	.wrclock(clk_sys),
	.wraddress(sdram_addr[14:0]),
	.wren(sdram_wr && (sdram_addr[23:15] == 2)),
	.byteena_a(sdram_ds),
	.data(sdram_din),

	.rdclock(clk_sys),
	.rdaddress(video_addr),
	.q(vram_dout)
);

/////////////////  ZX8301  ////////////////////////

wire video_r, video_g, video_b;
wire HS, VS;
wire HBlank, VBlank, ce_pix;

reg HSync, VSync;
always @(posedge CLK_VIDEO) begin
	HSync <= HS;
	if(~HSync & HS) VSync <= VS;
end

wire [1:0] scale = status[10:9];
assign VGA_SL = scale ? scale - 1'd1 : 2'd0;
assign VGA_F1 = 0;

assign CLK_VIDEO = clk_sys;

video_mixer #(.HALF_DEPTH(1), .GAMMA(1)) video_mixer
(
	.*,

	.clk_vid(CLK_VIDEO),
	.ce_pix(ce_pix),
	.ce_pix_out(CE_PIXEL),
	
	.scanlines(0),
	.scandoubler(scale || forced_scandoubler),
	.hq2x(scale==1),
	.mono(0),

	.R({4{video_r}}),
	.G({4{video_g}}),
	.B({4{video_b}})
);

wire [14:0] video_addr;

// the zx8301 has only one write-only register at $18063
wire zx8301_cs = cpu_cycle && cpu_io && ({cpu_addr[6:5], cpu_addr[1]} == 3'b111) && cpu_wr && !cpu_ds[0];

reg [7:0] mc_stat;
always @(posedge clk_sys) begin
	if(reset) mc_stat <= 8'h00;
	else if(ce_bus_p && zx8301_cs) mc_stat <= cpu_dout[7:0];
end

zx8301 zx8301
(
	.reset   ( reset      ),

	.clk     ( clk_sys    ),
	.ce      ( ce_vid     ),
	.ce_out  ( ce_pix     ),

	.ntsc    ( status[3]  ),
	.mc_stat ( mc_stat    ),

	.addr    ( video_addr ),
	.din     ( vram_dout  ),

	.hs      ( HS         ),
	.vs      ( VS         ),
	.r       ( video_r    ),
	.g       ( video_g    ),
	.b       ( video_b    ),
	.HBlank  ( HBlank     ),
	.VBlank  ( VBlank     )
);

/////////////////  ZX8302  ////////////////////////

wire zx8302_sel = cpu_cycle && cpu_io && !cpu_addr[6];
wire [1:0] zx8302_addr = {cpu_addr[5], cpu_addr[1]};
wire [15:0] zx8302_dout;

wire mdv_download = (ioctl_index == 1) && ioctl_download;

wire audio;
assign AUDIO_L = {15{audio}};
assign AUDIO_R = {15{audio}};
assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

wire mdv_led;

zx8302 zx8302
(
	.reset        ( reset        ),
	.reset_mdv    ( status[0]    ),
	.clk          ( clk_sys      ),
	.clk11        ( clk_11m      ),

	.xint         ( qimi_irq     ),
	.ipl          ( cpu_ipl      ),
	.led          ( mdv_led      ),
	.audio        ( audio        ),
	
	// CPU connection
	.cep          ( ce_bus_p     ),
	.cen          ( ce_bus_n     ),

	.ce_131k      ( ce_131k      ),
	.rtc_data     ( TIMESTAMP    ),

	.cpu_sel      ( zx8302_sel   ),
	.cpu_wr       ( cpu_wr       ),
	.cpu_addr     ( zx8302_addr  ),
	.cpu_ds       ( cpu_ds       ),
	.cpu_din      ( cpu_dout     ),
   .cpu_dout     ( zx8302_dout  ),

	// joysticks 
	.js0          ( joystick_0[4:0] ),
	.js1          ( joystick_1[4:0] ),

	.ps2_key      ( ps2_key      ),
	
	.vs           ( VSync        ),

	.mdv_reverse  ( status[2]    ),

	.mdv_download ( mdv_download ),
	.mdv_dl_wr    ( ioctl_wr && mdv_download),
	.mdv_dl_data  ( ioctl_dout   ),
	.mdv_dl_addr  ( ioctl_addr[17:1] )
);

/////////////////  MOUSE  /////////////////////////

// qimi is at 1bfxx
wire qimi_sel = cpu_io && (cpu_addr[13:8] == 6'b111111);
wire [7:0] qimi_data;
wire qimi_irq;
	
qimi qimi
(
   .reset     ( reset          ),
	.clk       ( clk_sys        ),
	.cep       ( ce_bus_p       ),
	.cen       ( ce_bus_n       ),

	.cpu_sel   ( qimi_sel       ),
	.cpu_addr  ( { cpu_addr[5], cpu_addr[1] } ),
	.cpu_data  ( qimi_data      ),
	.irq       ( qimi_irq       ),
	
	.ps2_mouse ( ps2_mouse      )
);

/////////////////  CPU  ///////////////////////////

reg [1:0] ram_cfg;
always @(posedge clk_sys) if(reset) ram_cfg <= status[5:4];

// address decoding
wire cpu_act  = cpu_rd || cpu_wr;
wire cpu_io   = cpu_act && ({cpu_addr[19:14], 2'b00} == 8'h18);   // internal IO $18000-$1bffff
wire cpu_bram = cpu_act &&(cpu_addr[19:17] == 3'b001);           	// 128k RAM at $20000
wire cpu_xram = cpu_act && ((|ram_cfg && ^cpu_addr[19:18]) || (ram_cfg[1] && &cpu_addr[19:18])); // ExtRAM 512k/768k
wire cpu_ram  = cpu_bram || cpu_xram;                   				// any RAM
wire cpu_rom  = cpu_act && (cpu_addr[19:16] == 4'h0);             // 64k ROM at $0

wire [15:0] io_dout = 
	qimi_sel?{qimi_data, qimi_data}:
	(!cpu_addr[6])?zx8302_dout:
	16'h0000;	

// demultiplex the various data sources
wire [15:0] cpu_din =
	qlsd_rd?{qlsd_dout, qlsd_dout}:    // qlsd maps into rom area
	cpu_rom?rom_dout:
	cpu_ram?sdram_dout:
	cpu_io?io_dout:
	16'hffff;

wire [31:0] cpu_addr;
wire [1:0] cpu_ds;
wire [15:0] cpu_dout;
wire [1:0] cpu_ipl;
wire cpu_rw;
wire [1:0] cpu_busstate;
wire cpu_rd = (cpu_busstate == 2'b00) || (cpu_busstate == 2'b10);
wire cpu_wr = (cpu_busstate == 2'b11) && !cpu_rw;
wire cpu_idle = (cpu_busstate == 2'b01);

reg cpu_enable;
always @(posedge clk_sys) if(ce_bus_n) cpu_enable <= cpu_cycle || cpu_idle;

TG68KdotC_Kernel #(0,0,0,0,0,0) tg68k
(
	.clk            ( clk_sys      ),
	.nReset         ( ~reset       ),
	.clkena_in      ( cpu_enable & ce_bus_p ), 
	.data_in        ( cpu_din      ),
	.IPL            ( {cpu_ipl[0], cpu_ipl }),  // ipl 0 and 2 are tied together on 68008
	.IPL_autovector ( 1'b1         ),
	.berr           ( 1'b0         ),
	.clr_berr       ( 1'b0         ),
	.CPU            ( 2'b00        ),   // 00=68000
	.addr           ( cpu_addr     ),
	.data_write     ( cpu_dout     ),
	.nUDS           ( cpu_ds[1]    ),
	.nLDS           ( cpu_ds[0]    ),
	.nWr            ( cpu_rw       ),
	.busstate       ( cpu_busstate ), // 00-> fetch code 10->read data 11->write data 01->no memaccess
	.nResetOut      (              ),
	.FC             (              )
);

//////////////////   SD LED   ///////////////////
reg sd_act;

always @(posedge clk_sys) begin
	reg old_mosi, old_miso;
	integer timeout = 0;

	old_mosi <= SD_MOSI;
	old_miso <= SD_MISO;

	sd_act <= 0;
	if(timeout < 4000000) begin
		timeout <= timeout + 1;
		sd_act <= 1;
	end

	if((old_mosi ^ SD_MOSI) || (old_miso ^ SD_MISO)) timeout <= 0;
end

endmodule
