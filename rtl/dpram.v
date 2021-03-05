module dpram #(parameter ADDRWIDTH=0, NUMWORDS=1<<ADDRWIDTH)
(
	input	                 wrclock,
	input	 [ADDRWIDTH-1:0] wraddress,
	input	                 wren,
	input	           [1:0] byteena_a,
	input	          [15:0] data,

	input	                 rdclock,
	input	 [ADDRWIDTH-1:0] rdaddress,
	output          [15:0] q
);

altsyncram	altsyncram_component (
			.address_a (wraddress),
			.address_b (rdaddress),
			.byteena_a (byteena_a),
			.clock0 (wrclock),
			.clock1 (rdclock),
			.data_a (data),
			.wren_a (wren),
			.q_b (q),
			.aclr0 (1'b0),
			.aclr1 (1'b0),
			.addressstall_a (1'b0),
			.addressstall_b (1'b0),
			.byteena_b (1'b1),
			.clocken0 (1'b1),
			.clocken1 (1'b1),
			.clocken2 (1'b1),
			.clocken3 (1'b1),
			.data_b ({16{1'b1}}),
			.eccstatus (),
			.q_a (),
			.rden_a (1'b1),
			.rden_b (1'b1),
			.wren_b (1'b0));
defparam
	altsyncram_component.address_aclr_b = "NONE",
	altsyncram_component.address_reg_b = "CLOCK1",
	altsyncram_component.byte_size = 8,
	altsyncram_component.clock_enable_input_a = "BYPASS",
	altsyncram_component.clock_enable_input_b = "BYPASS",
	altsyncram_component.clock_enable_output_b = "BYPASS",
	altsyncram_component.intended_device_family = "Cyclone V",
	altsyncram_component.lpm_type = "altsyncram",
	altsyncram_component.numwords_a = NUMWORDS,
	altsyncram_component.numwords_b = NUMWORDS,
	altsyncram_component.operation_mode = "DUAL_PORT",
	altsyncram_component.outdata_aclr_b = "NONE",
	altsyncram_component.outdata_reg_b = "UNREGISTERED",
	altsyncram_component.power_up_uninitialized = "FALSE",
	altsyncram_component.widthad_a = ADDRWIDTH,
	altsyncram_component.widthad_b = ADDRWIDTH,
	altsyncram_component.width_a = 16,
	altsyncram_component.width_b = 16,
	altsyncram_component.width_byteena_a = 2;

endmodule
