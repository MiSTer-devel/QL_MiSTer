//
// sdram.v
//
// sdram controller implementation for the MiST board
// https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module sdram (

	// interface to the MT48LC16M16 chip
	inout [15:0]  		SDRAM_DQ,    // 16 bit bidirectional data bus
	output reg [12:0]	SDRAM_A,    // 13 bit multiplexed address bus
	output reg      	SDRAM_DQMH,     // two byte masks
	output reg      	SDRAM_DQML,     // two byte masks
	output reg[1:0] 	SDRAM_BA,      // two banks
	output 				SDRAM_nCS,      // a single chip select
	output 				SDRAM_nWE,      // write enable
	output 				SDRAM_nRAS,     // row address select
	output 				SDRAM_nCAS,     // columns address select

	// cpu/chipset interface
	input 		 		init,			// init signal after FPGA config to initialize RAM
	input 		 		clk,			// sdram is accessed at up to 128MHz
	input					sync,  		// reference clock to sync to
	
	input [15:0]  		din,			// data input from chipset/cpu
	output reg [15:0] dout,			// data output to chipset/cpu
	input [23:0]   	addr,       // 25 bit word address
	input [1:0] 		ds,         // data strobe for hi/low byte
	input 		 		oe,         // cpu/chipset requests read
	input 		 		we          // cpu/chipset requests write
);

// no burst configured
localparam RASCAS_DELAY   = 3'd2;   // tRCD>=20ns -> 2 cycles@64MHz
localparam BURST_LENGTH   = 3'b000; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

localparam STATE_IDLE      = 3'd0;   // first state in cycle
localparam STATE_CMD_START = 3'd1;   // state in which a new command can be started
localparam STATE_CMD_CONT  = STATE_CMD_START + RASCAS_DELAY - 3'd1; // 4 command can be continued
localparam STATE_DOUT      = STATE_CMD_CONT  + CAS_LATENCY + 1'd1; // 4 command can be continued
localparam STATE_LAST      = 3'd7;   // last state in cycle

reg [2:0] q /* synthesis noprune */;
always @(posedge clk) if((q != STATE_LAST) || sync) q <= q + 1'd1;

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 1ms (32 clkref cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
reg [4:0] reset;
always @(posedge clk) begin
	if(init)	reset <= 5'h1f;
	else if((q == STATE_CMD_START) && (reset != 0)) // cannot use 0/7 values if clkref is not clk/8
		reset <= reset - 5'd1;
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg [3:0] sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign SDRAM_nCS  = sd_cmd[3];
assign SDRAM_nRAS = sd_cmd[2];
assign SDRAM_nCAS = sd_cmd[1];
assign SDRAM_nWE  = sd_cmd[0];

reg [1:0] state;
assign SDRAM_DQ = state[1] ? din : 16'bZZZZZZZZZZZZZZZZ;
//assign dout = SDRAM_DQ;

always @(posedge clk) begin
	sd_cmd <= CMD_INHIBIT;

	if(reset != 0) begin
		SDRAM_BA <= 2'b00;
		{SDRAM_DQMH,SDRAM_DQML} <= 2'b00;
			
		if(reset == 13) SDRAM_A <= 13'b0010000000000;
		else   			 SDRAM_A <= MODE;

		if(q == STATE_CMD_START) begin
			if(reset == 13)  sd_cmd <= CMD_PRECHARGE;
			if(reset ==  2)  sd_cmd <= CMD_LOAD_MODE;
		end
	end else begin
		if(q <= STATE_CMD_START) begin	
			SDRAM_A <= addr[20:8];
			SDRAM_BA <= addr[22:21];
			{SDRAM_DQMH,SDRAM_DQML} <= { !ds[1], !ds[0] };
		end else
			SDRAM_A <= { 4'b0010, addr[23], addr[7:0]};
	
		if(q == STATE_IDLE) begin
			state <= {we,oe};
			if(we || oe) sd_cmd <= CMD_ACTIVE;
			else         sd_cmd <= CMD_AUTO_REFRESH;
		end else if(q == STATE_CMD_CONT) begin
			if(state[1]) sd_cmd <= CMD_WRITE;
			else if(state[0]) sd_cmd <= CMD_READ;
		end else if(q == STATE_DOUT) begin
			if(state[0]) dout <= SDRAM_DQ;
		end
	end
end

endmodule
