//
// mdv.v - Microdrive
//
// Sinclair QL for the MiST
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

module mdv
(
   input        clk,   			// System clock (84mHz)
   input        ce,				// CPU clock
	input        reset,
	
	input        reverse,
	
	input        sel,

   // control bits	
	output       gap,
	output       tx_empty,
	output       rx_ready,
	output [7:0] dout,

	// ram interface to read image
	input        download,
	input [16:0] dl_addr,
	input [15:0] dl_data,
	input        dl_wr
);

reg  [16:0] mem_addr;
wire [15:0] mdv_din;

dpram #(17, 88000) vram
(
	.wrclock(clk),
	.wraddress(dl_addr),
	.wren(dl_wr),
	.byteena_a(2'b11),
	.data(dl_data),

	.rdclock(clk),
	.rdaddress(mem_addr),
	.q(mdv_din)
);

// a gap is permanently present if no mdv is inserted or if
// there's a gap on the inserted one. This is the signal that triggers
// the irq and can be seen by the cpu
assign gap = (!mdv_present) || mdv_gap /* synthesis keep */;  

// the mdv_rx_ready flag must be quite short as the CPU never waist for it to end
wire mdv_valid = (mdv_bit_cnt[2:0] == 2);
assign rx_ready = mdv_present && mdv_data_valid && mdv_valid;
assign tx_empty = 1'b0;

// microdrive implementation works with images which are uploaded by the user into
// the BRAM. It is then continously replayed from there at 200kbit/s

// determine mdv image size after download
reg [16:0] mdv_end;
always @(posedge clk or posedge reset) begin
	if(reset) mdv_end <= 0;
	else begin
		if(dl_wr) mdv_end <= dl_addr;
	end
end

// the microdrive at 200kbit/s reads a bit every 8.3us and needs a new word
// every 80us.
// gaps are 2800/3400 us which is 35 words at 200kbit/s

assign dout = mdv_bit_cnt[3]?mdv_data[7:0]:mdv_data[15:8];

// a microdrive image is present if at least one word is in the buffer
wire mdv_present = sel && (mdv_end != 0);
reg [3:0] mdv_bit_cnt /* synthesis noprune */;

// also generate gap timing
reg [15:0] mdv_data;
reg mdv_data_valid;
reg mdv_gap;

// microdrive clock runs at 200khz
// -> new word required every 80us
localparam mdv_clk_scaler = 7500000/(200000)-1;

always @(posedge clk) begin
	reg [9:0] mdv_gap_cnt;
	reg mdv_gap_state;
	reg mdv_gap_active;
	reg [7:0] mdv_clk_cnt;

	if(download) begin
		mem_addr <= 0;
		
		// assume we start at the end of a post-sector/pre-header gap
		mdv_gap_cnt <= 10'd0;      // count bytes until gap
		mdv_gap_state <= 1'b1;      // toggle header + data gap
		mdv_gap_active <= 1'b1;     // gap atm
		mdv_gap <= 1'b1; 
	end

	if(ce) begin
		if(mdv_clk_cnt == mdv_clk_scaler) mdv_clk_cnt <= 0;
		else mdv_clk_cnt <= mdv_clk_cnt + 1'd1;

		if(!mdv_clk_cnt) begin
			mdv_bit_cnt <= mdv_bit_cnt + 4'd1;
			if(mdv_bit_cnt == 15) begin
				mdv_data <= mdv_din;
				mdv_data_valid <= !mdv_gap_active && (mdv_gap_cnt > 5) && !(mdv_gap_state && (mdv_gap_cnt > 7) && (mdv_gap_cnt < 12));

				// reset counters when address is out of range
				if(mem_addr > mdv_end) begin
					mem_addr <= 0;

					// assume we start at the end of a post-sector/pre-header gap
					mdv_gap_cnt <= 10'd0;      // count bytes until gap
					mdv_gap_state <= 1'b1;      // toggle header + data gap
					mdv_gap_active <= 1'b1;     // gap atm
					mdv_gap <= 1'b1; 
				end else begin
					mdv_gap_cnt <= mdv_gap_cnt + 10'd1;
								
					if(mdv_gap_active) begin

						// stop sending gap after 35 words = 70 bytes = 2800us
						if(mdv_gap_cnt == 34) begin
							mdv_gap_cnt <= 10'd0;            // restart counter until next gap
							mdv_gap_active <= 1'b0;          // no gap anymore
							mdv_gap_state <= !mdv_gap_state; // toggle gap/data
							mdv_gap <= 1'b0;
						end
					end else begin
						mem_addr <= mem_addr + 1'd1;

						if((!mdv_gap_state) && (mdv_gap_cnt == 13)) begin
							// done reading 14 words header data
							mdv_gap_cnt <= 10'd0;            // restart counter for gap
							mdv_gap_active <= 1'b1;          // now comes a gap
							mdv_gap <= 1'b1;
						end else if(mdv_gap_state && (mdv_gap_cnt == 328)) begin
							// done reading 330 words sector data
							mdv_gap_cnt <= 10'd0;            // restart counter for gap
							mdv_gap_active <= 1'b1;          // now comes a gap
							mdv_gap <= 1'b1;

							if(reverse) begin
								// The sectors on cartridges are written in descending order
								// Some images seem to contain them in ascending order. So we
								// have to replay them backwards for better performance

								if(mem_addr == 343 - 1)
									mem_addr <= mdv_end  - 17'd343 + 1'd1;
								else
									mem_addr <= mem_addr - 17'd686 + 1'd1;
							end
						end
					end
				end
			end
		end
	end
end

endmodule
