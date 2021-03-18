//
// sdram.sv
//
// Copyright (c) 2019 Marcel Kilgus
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

/*
	Asynchronous SDRAM controller for the Sinclair QL implementation on the
	MiSTer FPGA board. Used in conjunction with the FX68k CPU core by ijor.
	
	It is specially designed for use with the 68k memory cycle. Writes are
	cached and thus don't introduce any wait states and they alwas finish 
	before the next possible cycle.
	
	Reads are generally served with two wait states, but as an optimisation
	reads are always 32-bit so that the subsequent read to the second halve
	of a 32-bit value can be satisfied immediately.
*/	
 
module sdram (
	// interface to the MT48LC16M16 chip
	inout reg [15:0] 	SDRAM_DQ,    	// 16 bit bidirectional data bus
	output reg [12:0]	SDRAM_A,    	// 13 bit multiplexed address bus
	output 	      	SDRAM_DQMH,    // two byte masks
	output 	      	SDRAM_DQML,    // two byte masks
	output reg[1:0] 	SDRAM_BA,      // two banks
	output 				SDRAM_nCS,     // a single chip select
	output 				SDRAM_nWE,     // write enable
	output 				SDRAM_nRAS,    // row address select
	output 				SDRAM_nCAS,    // columns address select
	output				SDRAM_CLK,

	// cpu/chipset interface
	input 		 		init,				// init signal after FPGA config to initialize RAM
	input					clk,  			// sdram is accessed at up to 128MHz
	input 		 		refresh,			// some clock input to start regular refresh cycle (> 128 kHz)
	
	input [15:0]  		din,				// data input from chipset/cpu
	output reg [15:0] dout,				// data output to chipset/cpu
	input [23:0]   	addr,       	// 25 bit word address
	input       		uds,         	// data strobe for hi byte
	input       		lds,         	// data strobe for low byte
	input 		 		oe,         	// cpu/chipset requests read
	input 		 		we,          	// cpu/chipset requests write
	output reg			dtack				// data acknowledge
);

// No burst configured
localparam BURST_LENGTH   = 3'b000; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ----------------------- finite state machine ------------------------
// ---------------------------------------------------------------------

typedef enum reg [3:0] {
	STATE_IDLE      			= 4'd0,
	STATE_WAIT					= 4'd1,
	STATE_READ_RASCAS_1		= 4'd2,
	STATE_READ_RASCAS_2		= 4'd3,
	STATE_READ_CMD				= 4'd4,
	STATE_READ_CAS_1  		= 4'd5,
	STATE_READ_CAS_2  		= 4'd6,
	STATE_READ_DELAY 	 		= 4'd7,
	STATE_READ_DATA_1 		= 4'd8,
	STATE_READ_DATA_2 		= 4'd9,
	STATE_WRITE_RASCAS_1		= 4'd10,
	STATE_WRITE_RASCAS_2		= 4'd11,
	STATE_WRITE_CMD			= 4'd12,
	STATE_WRITE_DELAY_1		= 4'd13,
	STATE_WRITE_DELAY_2		= 4'd14
} sd_state_t;


reg doRefresh;
reg [8:0]  save_col;
reg [23:0] cache_addr /* synthesis noprune */;
reg [15:0] cache_data /* synthesis noprune */;

localparam REFRESH_CYCLES = 6;		// tRFC = 60ns = 5 cycles @ 84Mhz

task doWait(input [7:0] cycles, input sd_state_t state);
	begin
		waitCycles <= cycles;
		waitState <= state;
		q <= STATE_WAIT;
	end
endtask
	
reg [7:0] waitCycles;
sd_state_t waitState;

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

reg [5:0] reset;
always @(posedge clk) begin
	if (init)
	begin
		reset <= 6'h3f;
	end else if (reset != 0)
		reset <= reset - 6'd1;
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
typedef enum reg [3:0] {
	CMD_INHIBIT         = 4'b1111,
	CMD_NOP             = 4'b0111,
	CMD_ACTIVE          = 4'b0011,
	CMD_READ            = 4'b0101,
	CMD_WRITE           = 4'b0100,
	CMD_BURST_TERMINATE = 4'b0110,
	CMD_PRECHARGE       = 4'b0010,
	CMD_AUTO_REFRESH    = 4'b0001,
	CMD_LOAD_MODE       = 4'b0000
} sd_cmd_t;

sd_cmd_t sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign SDRAM_nCS  = sd_cmd[3];
assign SDRAM_nRAS = sd_cmd[2];
assign SDRAM_nCAS = sd_cmd[1];
assign SDRAM_nWE  = sd_cmd[0];
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];	// For SDRAM v1 compatibility I assume

// Address translation
// CPU: A24 A23 A22 A21 A20 A19 A18 A17 A16 A15 A14 A13 A12 A11 A10 A09 A08 A07 A06 A05 A04 A03 A02 A01 A00
// BUS: A23 A22 A21 A20 A19 A18 A17 A16 A15 A14 A13 A12 A11 A10 A09 A08 A07 A06 A05 A04 A03 A02 A01 A00
// RAM: B01 B00 R12 R11 R10 R09 R08 R07 R06 R05 R04 R03 R02 R01 R00 C08 C07 C06 C05 C04 C03 C02 C01 C00 DQMH/L 
//     | Banks | Rows                                              | Columns                           | H/L

sd_state_t q /* synthesis noprune */;
always @(posedge clk)
begin
	reg [1:0] dqm;		// Captures UDS/LDS as the DQM lines are multiplexed and can only be asserted later
	reg [15:0] dq_reg;
	
	sd_cmd <= CMD_INHIBIT;
	SDRAM_DQ <= 16'bZ;
	dq_reg <= SDRAM_DQ;

	if (reset != 0) 
	begin		
		// Reset sequence. Somewhat relaxed timing
		SDRAM_BA <= 2'b00;
			
		if (reset == 24)
		begin
			SDRAM_A <= 13'b0010000000000;			// Precharge all banks
			sd_cmd <= CMD_PRECHARGE;
		end
		else if (reset == 10 || reset == 20)
		begin
			sd_cmd <= CMD_AUTO_REFRESH;			// Do auto-refresh (2x)
		end
		else if (reset == 2)
		begin
			SDRAM_A <= MODE;
			sd_cmd <= CMD_LOAD_MODE;				// Finally, load mode
			q <= STATE_IDLE;
		end
	end else begin
		if (!we && !oe) dtack <= 0;				// Memory access is over, release dtack
		
		if (refresh) doRefresh <= 1;				// Remember to do refresh the next time we're ready

		case (q)
		STATE_IDLE:
			begin
				// Pre-select row
				SDRAM_A <= addr[21:9];
				SDRAM_BA <= addr[23:22];
				
				// Refresh has priority
				if (refresh || doRefresh)
				begin
					// Start refresh cycle
					doRefresh <= 0;
					sd_cmd <= CMD_AUTO_REFRESH;	// Do auto-refresh

					doWait(REFRESH_CYCLES, STATE_IDLE);	// Continue to idle after wait
				end
				else if (oe && !dtack)
				begin
					if (addr == cache_addr)
					begin
						dout <= cache_data;			// We can satisfy the read from cache, cool
						dtack <= 1;						// ... aaaaaand we're done
					end else begin
						cache_addr <= {addr[23:9], addr[8:0] + 9'd1};	// We will cache the next word, too (wrap on row border)
						sd_cmd <= CMD_ACTIVE;		// Activate row						
						q <= STATE_READ_RASCAS_1;
					end
				end
				else if (we && !dtack)
				begin
					save_col <= addr[8:0];			// Save column

					dtack <= 1;							// ... so CPU can continue without any waitstates
					sd_cmd <= CMD_ACTIVE;			// Activate row
					q <= STATE_WRITE_RASCAS_1;
				end
			end

		// Generic wait state (waitCycles-1 cycles)
		STATE_WAIT:
			begin
				waitCycles <= waitCycles - 8'd1;
				if (waitCycles == 1) q <= waitState;
			end
		
		// Read states
		STATE_READ_RASCAS_1:
			q <= STATE_READ_RASCAS_2;				// Wait tRCD = 18ns (2 cycles up to 111Mhz)
			
		STATE_READ_RASCAS_2:
			q <= STATE_READ_CMD;
			
		STATE_READ_CMD:
			begin
				SDRAM_A <= {4'b0000, addr[8:0]};	// Select column of read data. A10 = 0 for no auto-precharge
				sd_cmd <= CMD_READ;					// Start main read
				q <= STATE_READ_CAS_1;
			end

		STATE_READ_CAS_1:
			begin
				SDRAM_A <= {4'b0010, cache_addr[8:0]};	// Select column of cache data. A10 = 1 for auto-precharge, A12/A11 = DQMH/DQML
				sd_cmd <= CMD_READ;					// Start next read for 2nd halve of long-word
				q <= STATE_READ_CAS_2;
			end
			
		STATE_READ_CAS_2:
			begin
				dtack <= 1;								// We can assert DTACK two cycles before providing the data
				q <= STATE_READ_DELAY;				// CAS delay is configured for 2 cycles
			end

		STATE_READ_DELAY:
			q <= STATE_READ_DATA_1;

		STATE_READ_DATA_1:
			begin
				dout <= dq_reg;						// Main data we're after
				q <= STATE_READ_DATA_2;
			end

		STATE_READ_DATA_2:
			begin
				cache_data <= dq_reg;				// 2nd halve of long-word, cache it, it'll pretty likely be needed soon
				doWait(1, STATE_IDLE); 				// Wait tRP = 18ns for auto-precharge (2 cycles up to 111Mhz)
			end
			
		// Write states
		STATE_WRITE_RASCAS_1:
			if (uds || lds)							// Wait here for STATE 4 in 68000 cycle
			begin
				if (uds && lds)
				begin
					cache_addr <= addr;				// Cache data in case of a read-back of the same
					cache_data <= din;
				end else begin
					cache_addr <= 0;					// Byte access, just invalidate cache
				end
			
				dqm <= {!uds, !lds};					// We've already asserted dtack, these will be invalid soon
				SDRAM_DQ <= din;
				q <= STATE_WRITE_RASCAS_2;			// Wait tRCD = 18ns (2 cycles up to 111Mhz)						
			end
			
		STATE_WRITE_RASCAS_2:
			q <= STATE_WRITE_CMD;
			
		STATE_WRITE_CMD:
			begin
				SDRAM_A <= {dqm, 2'b10, save_col};	// Select column of write data. A10 = 1 for auto-precharge, A12/A11 = DQMH/DQML
				sd_cmd <= CMD_WRITE;
				q <= STATE_WRITE_DELAY_1;
			end
			
		STATE_WRITE_DELAY_1:
			q <= STATE_WRITE_DELAY_2;				// Wait tRP = 18ns for auto-precharge (2 cycles up to 111Mhz)
			
		STATE_WRITE_DELAY_2:		
			q <= STATE_IDLE;
		endcase
	end
end

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
