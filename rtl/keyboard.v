//
// keyboard.v
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

module keyboard ( 
	input clk,
   input ce_11m,
	input reset,

	// ps2 interface	
	input [10:0] ps2_key,

	input [4:0] js0,
	input [4:0] js1,
	
	output [63:0] matrix
);

assign matrix = ql_matrix | special_matrix;

// 8x8 ql keyboard matrix
reg [63:0] ql_matrix;

// small matrix for special keys (backspace, ...)
reg [11:0] special;

// check which ql keys are triggered by the special keys
wire x_shift = special[0]  || special[3]  || special[4]   || special[7] ||
			  	   special[8]  || special[9]  || special[10]  || special[11];
wire x_ctrl  = special[1]  || special[2];
wire x_alt   = special[5]  || special[6];

wire x_left  = specialD[1] || specialD[5] || js1[1];
wire x_right = specialD[2] || specialD[6] || js1[0];
wire x_up    = specialD[3] || js1[3];
wire x_down  = specialD[4] || js1[2];
wire x_space = js1[4];

wire x_f1    = specialD[7] || js0[1];
wire x_f2    = specialD[8] || js0[2];
wire x_f3    = specialD[9] || js0[0];
wire x_f4    = specialD[10]|| js0[3];
wire x_f5    = specialD[11]|| js0[4];

// Divide 11MHz clock down to ~1khz some delay
reg ce_1k;
always @(posedge clk) begin
	reg [12:0] clk_delay_cnt;  // 11MHz / 8192 = 1.342kHz

	ce_1k <= 0;
	if (ce_11m) begin
		clk_delay_cnt <= clk_delay_cnt + 1'd1;
		ce_1k <= !clk_delay_cnt;
	end
end

// The "main" key of a combined modifier key needs to be delayed. Otherwise
// the QL will not accept it. E.g. when pressing CTRL-LEFT, the CTRL key needs
// to be pressed first. Pressing both at the same time won't work. We thus delay
// the "other" key like e.g. the LEFT key. Both are released at the same time
wire [11:1] specialD;
delay delay_1( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[1]), .out(specialD[1]) );
delay delay_2( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[2]), .out(specialD[2]) );
delay delay_3( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[3]), .out(specialD[3]) );
delay delay_4( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[4]), .out(specialD[4]) );
delay delay_5( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[5]), .out(specialD[5]) );
delay delay_6( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[6]), .out(specialD[6]) );
delay delay_7( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[7]), .out(specialD[7]) );
delay delay_8( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[8]), .out(specialD[8]) );
delay delay_9( .clk(clk), .ce(ce_1k), .reset(reset), .in(special[9]), .out(specialD[9]) );
delay delay_10(.clk(clk), .ce(ce_1k), .reset(reset), .in(special[10]),.out(specialD[10]));
delay delay_11(.clk(clk), .ce(ce_1k), .reset(reset), .in(special[11]),.out(specialD[11]));

// map the special keys onto the matrix which is then or'd with the
// normal matrix
wire [63:0] special_matrix = {
   5'b00000, x_alt, x_ctrl, x_shift, 
	8'b00000000,
	8'b00000000,
	8'b00000000,
	8'b00000000,
	8'b00000000,
	x_down, x_space, 1'b0, x_right, 1'b0, x_up, x_left, 1'b0,
	2'b00, x_f5, x_f3, x_f2, 1'b0, x_f1, x_f4
};

// ================================= layout =============================
// F1     ESC  1   2   3   4   5   6   7   8   9   0   -   =   £   \
// F2     TAB    Q   W   E   R   T   Y   U   I   O   P   [   ]
// F3     CAPS    A   S   D   F   G   H   J   K   L   ;   '      ENTER
// F4     SHIFT     Z   X   C   V   B   N   M   ,   .   /     SHIFT
// F5     CTRL  LEFT RIGHT          SPACE             UP  DOWN   ALT 



// ================================== matrix ============================
//        0      1      2      3      4      5      6      7
//  +-------------------------------------------------------
// 0|    F4     F1      5     F2     F3     F5      4      7
// 1|   Ret   Left     Up    Esc  Right      \  Space   Down
// 2|     ]      z      .      c      b  Pound      m      '
// 3|     [   Caps      k      s      f      =      g      ;
// 4|     l      3      h      1      a      p      d      j
// 5|     9      w      i    Tab      r      -      y      o
// 6|     8      2      6      q      e      0      t      u
// 7| Shift   Ctrl    Alt      x      v      /      n      ,

wire pressed    = ps2_key[9];
wire [7:0] code = ps2_key[7:0];

always @(posedge clk) begin
	reg old_stb;
	old_stb <= ps2_key[10];

	if(reset) begin
		ql_matrix <= 64'd0;
		special <= 12'd0;
	end else begin

		// ps2 decoder has received a valid code
		if(old_stb != ps2_key[10]) begin

			case(code)
				// modifier keys
				8'h12:  ql_matrix[8*7+0] <= pressed; // (left) SHIFT
				8'h14:  ql_matrix[8*7+1] <= pressed; // CTRL
				8'h11:  ql_matrix[8*7+2] <= pressed; // ALT

				// function keys
				8'h05:  ql_matrix[8*0+1] <= pressed; // F1
				8'h06:  ql_matrix[8*0+3] <= pressed; // F2
				8'h04:  ql_matrix[8*0+4] <= pressed; // F3
				8'h0c:  ql_matrix[8*0+0] <= pressed; // F4
				8'h03:  ql_matrix[8*0+5] <= pressed; // F5

				// cursor keys
				8'h75:  ql_matrix[8*1+2] <= pressed; // Up
				8'h72:  ql_matrix[8*1+7] <= pressed; // Down
				8'h6b:  ql_matrix[8*1+1] <= pressed; // Left
				8'h74:  ql_matrix[8*1+4] <= pressed; // Right

				8'h1c:  ql_matrix[8*4+4] <= pressed; // a
				8'h32:  ql_matrix[8*2+4] <= pressed; // b
				8'h21:  ql_matrix[8*2+3] <= pressed; // c
				8'h23:  ql_matrix[8*4+6] <= pressed; // d
				8'h24:  ql_matrix[8*6+4] <= pressed; // e
				8'h2b:  ql_matrix[8*3+4] <= pressed; // f
				8'h34:  ql_matrix[8*3+6] <= pressed; // g
				8'h33:  ql_matrix[8*4+2] <= pressed; // h
				8'h43:  ql_matrix[8*5+2] <= pressed; // i
				8'h3b:  ql_matrix[8*4+7] <= pressed; // j
				8'h42:  ql_matrix[8*3+2] <= pressed; // k
				8'h4b:  ql_matrix[8*4+0] <= pressed; // l
				8'h3a:  ql_matrix[8*2+6] <= pressed; // m
				8'h31:  ql_matrix[8*7+6] <= pressed; // n
				8'h44:  ql_matrix[8*5+7] <= pressed; // o
				8'h4d:  ql_matrix[8*4+5] <= pressed; // p
				8'h15:  ql_matrix[8*6+3] <= pressed; // q
				8'h2d:  ql_matrix[8*5+4] <= pressed; // r
				8'h1b:  ql_matrix[8*3+3] <= pressed; // s
				8'h2c:  ql_matrix[8*6+6] <= pressed; // t	
				8'h3c:  ql_matrix[8*6+7] <= pressed; // u
				8'h2a:  ql_matrix[8*7+4] <= pressed; // v
				8'h1d:  ql_matrix[8*5+1] <= pressed; // w
				8'h22:  ql_matrix[8*7+3] <= pressed; // x
				8'h35:  ql_matrix[8*5+6] <= pressed; // y
				8'h1a:  ql_matrix[8*2+1] <= pressed; // z

				8'h45:  ql_matrix[8*6+5] <= pressed; // 0
				8'h16:  ql_matrix[8*4+3] <= pressed; // 1
				8'h1e:  ql_matrix[8*6+1] <= pressed; // 2
				8'h26:  ql_matrix[8*4+1] <= pressed; // 3
				8'h25:  ql_matrix[8*0+6] <= pressed; // 4
				8'h2e:  ql_matrix[8*0+2] <= pressed; // 5
				8'h36:  ql_matrix[8*6+2] <= pressed; // 6
				8'h3d:  ql_matrix[8*0+7] <= pressed; // 7
				8'h3e:  ql_matrix[8*6+0] <= pressed; // 8
				8'h46:  ql_matrix[8*5+0] <= pressed; // 9

				8'h5a:  ql_matrix[8*1+0] <= pressed; // RET
				8'h29:  ql_matrix[8*1+6] <= pressed; // SPACE
				8'h0d:  ql_matrix[8*5+3] <= pressed; // TAB
				8'h76:  ql_matrix[8*1+3] <= pressed; // ESC	
				8'h58:  ql_matrix[8*3+1] <= pressed; // CAPS

				8'h4e:  ql_matrix[8*5+5] <= pressed; // -
				8'h55:  ql_matrix[8*3+5] <= pressed; // =
				8'h61:  ql_matrix[8*2+5] <= pressed; // Pound
				8'h5d:  ql_matrix[8*1+5] <= pressed; // \

				8'h54:  ql_matrix[8*3+0] <= pressed; // [
				8'h5b:  ql_matrix[8*2+0] <= pressed; // ]

				8'h4c:  ql_matrix[8*3+7] <= pressed; // ;
				8'h52:  ql_matrix[8*2+7] <= pressed; // '

				8'h41:  ql_matrix[8*7+7] <= pressed; // ,
				8'h49:  ql_matrix[8*2+2] <= pressed; // .
				8'h4a:  ql_matrix[8*7+5] <= pressed; // /

				// special keys that include modifier
				8'h59:  special[0]  <= pressed;      // SHIFT
				8'h66:  special[1]  <= pressed;      // Backspace -> CTRL+LEFT
				8'h71:  special[2]  <= pressed;      // Delete -> CTRL+RIGHT
				8'h7d:  special[3]  <= pressed;      // PageUp -> SHIFT+UP
				8'h7a:  special[4]  <= pressed;      // PageDown -> SHIFT+DOWN
				8'h6c:  special[5]  <= pressed;      // Home -> ALT+LEFT
				8'h69:  special[6]  <= pressed;      // End -> ALT+RIGHT
				8'h0b:  special[7]  <= pressed;      // F6 -> SHIFT+F1
				8'h83:  special[8]  <= pressed;      // F7 -> SHIFT+F2
				8'h0a:  special[9]  <= pressed;      // F8 -> SHIFT+F3
				8'h01:  special[10] <= pressed;      // F9 -> SHIFT+F4
				8'h09:  special[11] <= pressed;      // F10 -> SHIFT+F5
			endcase
		end
	end
end

endmodule

// add delay to special combo keys
module delay (
	input clk,
	input ce,
	input reset,
	input in,
	output out
);

reg [4:0] delay_cnt;
assign out = delay_cnt[4] & in;

always @(posedge clk) begin
	if(reset | ~in)           delay_cnt <= 0;
	else if(ce & ~&delay_cnt) delay_cnt <= delay_cnt + 1'd1;
end

endmodule // delay
