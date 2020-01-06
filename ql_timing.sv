// QL RAM timing simulation
//
// Copyright (C) 2019 Marcel Kilgus
//
// Much of the original QL RAM is used to generate the video signal. This module tries to slow
// down the SDRAM access similarly to the original timing

module ql_timing
(
	input			clk_sys,
	input  		reset,
	input			enable,
	input			ce_bus_p,
	
	input			cpu_uds,
	input			cpu_lds,
	
	input			sdram_wr,
	input			sdram_oe,
	input			sdram_dtack,

	output reg	ram_delay_dtack
);


reg [5:0] chunk;					// We got 40 chunks per display line...
reg [3:0] chunkCycle;			// ...with 12 cycles per chunk

// In chunks 0..31 the CPU only gets the last 4 cycles in the 12 cycle chunk.
// And as an access takes 4 cycles only cycle 8 can start a new access
// Similarly in chunk 39 an access can only start at cycle 8 at the latest
wire could_start = 
		chunk < 6'd32 && chunkCycle == 4'd8
	|| chunk >= 6'd32 && chunk < 6'd39
	|| chunk == 6'd39 && chunkCycle <= 4'd8;

// 00 01 02 03 04 05 06 07 08 09 10 11 00 01 02 03 04 05 06 07 08 09 10 11
//                       I W4 D1  I
// ________________________------_________________________________________  8-bit access allowed, delay dtack 2 cycles
//              I WS WS WS WS D1  I
// _______________---------------_________________________________________  8-bit access must wait, delay dtack to 3rd cycle in next slot
//                       I W4 S3 S2 S1 WN D1  I
// ________________________------------------_____________________________  16-bit access allowed, chunk 32+
//              I WS WS WS WS S3 S2 S1 WN WN WN WN WN WN WN WN WN D1  I
// _______________---------------------------------------------------_____  16-bit access must wait, chunk < 32
typedef enum reg [2:0] {
	STATE_IDLE				= 3'd0,
	STATE_WAIT_START		= 3'd1,
	STATE_WAIT_S4			= 3'd2,
	STATE_SKIP_SLOT_3		= 3'd3,
	STATE_SKIP_SLOT_2		= 3'd4,
	STATE_SKIP_SLOT_1		= 3'd5,
	STATE_WAIT_NEXT		= 3'd6,
	STATE_DTACK_1			= 3'd7
} ram_delay_state_t;

ram_delay_state_t ram_delay_state;

always @(posedge clk_sys)
begin
	if (reset || !enable)
	begin
		chunk <= 0;
		chunkCycle <= 0;
		ram_delay_dtack <= 0;
		ram_delay_state <= STATE_IDLE;
	end else
	begin
		// Idle state (check for RAM access start) must be processed outside of the bus cycle ce_bus_p as the 
		// SDRAM is clocked at clk_sys speed and we would miss it otherwise
		if (ram_delay_state == STATE_IDLE)
		begin
			// Wait for RAM accesss
			if ((sdram_wr || sdram_oe) && !sdram_dtack)
			begin
				// CPU wants to access the RAM. Let it, but delay dtack to the point when a QL would have asserted it
				ram_delay_dtack <= 1;
				ram_delay_state <= could_start? STATE_WAIT_S4: STATE_WAIT_START;
			end
		end
	
		if (ce_bus_p)
		begin
			chunkCycle <= chunkCycle + 4'd1;
			if (chunkCycle == 4'd11)
			begin
				chunkCycle <= 4'd0;
				chunk <= chunk + 6'd1;
				if (chunk == 6'd39) chunk <= 6'd0;
			end

			case (ram_delay_state)
			// Access could not start yet, wait for it
			STATE_WAIT_START:
				if (could_start)
				begin
					if (cpu_uds && cpu_lds)
						// 16-bit accesses must be delayed a whole slot more as the QL only had an 8-bit bus
						ram_delay_state <= STATE_SKIP_SLOT_3;
					else begin
						ram_delay_state <= STATE_DTACK_1;
					end
				end
			
			// We're now on STATE 4 in the memory cycle, now uds/lds are also set for write accesses
			STATE_WAIT_S4:
				if (cpu_uds && cpu_lds)
					// 16-bit accesses must be delayed a whole slot more as the QL only had an 8-bit bus
					ram_delay_state <= STATE_SKIP_SLOT_3;
				else begin
					ram_delay_state <= STATE_DTACK_1;
				end
				
			// Wait 3 more cycles to skip slot
			STATE_SKIP_SLOT_3:
				ram_delay_state <= STATE_SKIP_SLOT_2;
				
			// Wait 2 more cycles to skip slot
			STATE_SKIP_SLOT_2:
				ram_delay_state <= STATE_SKIP_SLOT_1;
				
			// Wait one more cycles to skip slot
			STATE_SKIP_SLOT_1:
				ram_delay_state <= STATE_WAIT_NEXT;
				
			// Wait for next slot to start
			STATE_WAIT_NEXT:
				if (could_start) ram_delay_state <= STATE_DTACK_1;
			
			// Stop delaying DTACK
			STATE_DTACK_1:
				begin
					ram_delay_dtack <= 0;
					ram_delay_state <= STATE_IDLE;
				end				
			endcase
		end
	end
end

endmodule