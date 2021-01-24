// QL RAM timing simulation
//
// Copyright (C) 2019 Marcel Kilgus
// Copyright (c) 2021 Daniele Terdina
//
// Much of the original QL RAM is used to generate the video signal. This module tries to slow
// down the SDRAM access similarly to the original timing

module ql_timing
(
	input			clk_sys,
	input  		reset,
	input			enable,
	input			ce_bus_p,
	input			VBlank,
	
	input			cpu_uds,
	input			cpu_lds,
	input       cpu_rw,
	input			cpu_rom,


	output reg	ram_delay_dtack
);


reg [5:0] chunk;					// We got 40 chunks per display line...
reg [3:0] chunkCycle;			// ...with 12 cycles per chunk

wire [5:0] num_busy_chunks = VBlank ? 6'd8 : 6'd32;	// 32 chunks used by ZX8301 for video, 8 during vblank for RAM refresh
wire could_start = chunk >= num_busy_chunks || chunkCycle == 4'd0; // For used chunks, the CPU can only access RAM in-between 


wire ds;
assign ds = cpu_uds || cpu_lds;
reg prev_ds;


reg [2:0] dtack_count;
reg extra_access;

always @(posedge clk_sys)
begin
	if (reset || !enable)
	begin
		chunk <= 0;
		chunkCycle <= 0;
		ram_delay_dtack <= 0;
	end 
	else
	begin
		if (ce_bus_p)
		begin
			chunkCycle <= chunkCycle + 4'd1;
			if (chunkCycle == 4'd11)
			begin
				chunkCycle <= 4'd0;
				if (chunk == 6'd39) 
					chunk <= 6'd0;
				else
					chunk <= chunk + 6'd1;
			end

			if (ds && ~prev_ds)
			begin
				// New bus access. ZX8301 takes about 1 cycle before deciding whether to insert wait states.
				// ZX8301 only checks DS and not AS... as a result, at least one wait state is inserted for all writes.
				ram_delay_dtack <= 1;
				dtack_count <= 3'd1;
				extra_access <= cpu_uds && cpu_lds;	// 16bit access?
			end
			else
			begin
				if (dtack_count == 3'd1 && ram_delay_dtack)
				begin
					if (could_start || cpu_rom)
					begin
						if (extra_access)
						begin
							// For 16 bit access, add wait states to simulate the time it takes the 68008
							// to complete a second bus access
							dtack_count <= cpu_rw ? 3'd4 : 3'd5;
							extra_access <= 0;
						end
						else
						begin
							ram_delay_dtack <= 0;
						end
					end
				end
				else
				begin
					dtack_count <= dtack_count - 3'd1;
				end
			end
			prev_ds <= ds;
		end
	end
end

endmodule