//
// qimi.v - Ql mouse Interface
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

module qimi
( 
	input clk,
	input cen,
	input cep,

	input reset,

	input  cpu_sel,
	input [1:0] cpu_addr,   // a5, a1
	output [7:0] cpu_data,
	output reg irq,
	
	input [24:0] ps2_mouse
);

// generate irq ack whenever cpu accesses 1bf9c
reg irq_ack;
always @(posedge clk) begin
	if(cen) begin
		irq_ack <= 1'b0;
		if(cpu_sel && cpu_addr == 2'b11)
			irq_ack <= 1'b1;
	end
end

wire x_dir = !x_pos[9];
wire y_dir = !y_pos[9];
wire x_mov = (x_pos != 0);
wire y_mov = (y_pos != 0);

assign cpu_data = 
	(cpu_addr == 2'b00)?{2'b00,!b[0],!b[1],4'b0000}:                  // 1bf9c
	(cpu_addr == 2'b10)?{2'b00,y_mov,x_dir,1'b0,x_mov,1'b0,y_dir }:   // 1bfbc
	8'h00;
	
// registers keeping state of current mouse state
reg [1:0] b;
reg [9:0] x_pos; 
reg [9:0] y_pos;

// counter to limit irq rate to 2khz
reg [11:0] irq_holdoff;

always @(posedge clk) begin
	reg old_stb;
	
	if(cep) begin
		old_stb <= ps2_mouse[24];

		if(reset) begin
			x_pos <= 10'd0;
			y_pos <= 10'd0;
			irq <= 1'b0;
			irq_holdoff <= 12'd0;
		end else begin
			// check if we have to fire another irq	
			if(irq_holdoff != 0) begin
				irq_holdoff <= irq_holdoff - 12'd1;
				if((irq_holdoff == 1) && (x_mov || y_mov))
					irq <= 1'b1;
			end
		
			if(old_stb != ps2_mouse[24]) begin

				b <= ps2_mouse[1:0];

				// the ps2 packet contains a 9 bit value. We only use the upper 
				// 7. Otherwise the mouse would be too fast for our low resolution
				x_pos <= x_pos + { {2{ps2_mouse[4]}}, ps2_mouse[15:8]};
				y_pos <= y_pos + { {2{ps2_mouse[5]}}, ps2_mouse[23:16]};
				
				if(irq_holdoff == 0)
					irq_holdoff <= 12'd1;

			end else begin
				// one bit has been reported to host
				if(irq_ack) begin
					if(x_pos != 0) begin
						if(x_pos[9]) x_pos <= x_pos + 10'd1;
						else         x_pos <= x_pos - 10'd1;
					end
					
					if(y_pos != 0) begin
						if(y_pos[9]) y_pos <= y_pos + 10'd1;
						else         y_pos <= y_pos - 10'd1;
					end

					// clear irq
					irq <= 1'b0;
					
					// next irq after some time ...
					irq_holdoff <= 12'd4000;
				end
			end
		end
	end
end

endmodule
