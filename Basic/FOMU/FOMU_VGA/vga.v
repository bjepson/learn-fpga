// Displays hypnotic moving circles with the FOMU
// Need to solder five wires to the FOMU (4 pads plus mass)
// See: https://twitter.com/mntmn/status/1281632873448124417
//      https://twitter.com/foone/status/1281740047461396480
//      https://github.com/mntmn/fomu-vga
 
`default_nettype none // Makes it easier to detect typos !

module vga (
   input  clki,     // ->48 Mhz clock input
   output rgb0,     // \
   output rgb1,     //  >LED
   output rgb2,     // /
   output user_1,   // ->hsync
   output user_2,   // ->vsync
   output user_3,   // ->color0
   output user_4,   // ->color1
   output usb_dp,   // \
   output usb_dn,   //  >USB pins (should be driven low if not used)
   output usb_dp_pu // /
);

   // USB pins driven low
   assign usb_dp=0;
   assign usb_dn=0;
   assign usb_dp_pu=0;

   wire   pixel_clk;

`define VGA_MODE_640x480
//`define VGA_MODE_1024x768
//`define VGA_MODE_1280x1024

`ifdef VGA_MODE_640x480
   // PLL: converts system clock (48 MHz) to pixel clock (25.125 MHz for 640x480)
   // icepll -i 48 -o 25.125
   SB_PLL40_CORE #(
     .FEEDBACK_PATH("SIMPLE"),
     .DIVR(4'b0011),
     .DIVF(7'b1000010),
     .DIVQ(3'b101),
     .FILTER_RANGE(3'b001),
   ) pll (
     .REFERENCECLK   (clki),
     .PLLOUTCORE     (pixel_clk),
     .BYPASS         (1'b0),
     .RESETB         (1'b1)
   );

   // Video mode constants
   parameter VGA_width         = 640;
   parameter VGA_height        = 480;
   parameter VGA_h_front_porch = 16;
   parameter VGA_h_sync_width  = 96;
   parameter VGA_h_back_porch  = 48;
   parameter VGA_v_front_porch = 10;
   parameter VGA_v_sync_width  = 2;
   parameter VGA_v_back_porch  = 32;
`endif

`ifdef VGA_MODE_1024x768
   // PLL: converts system clock (48 MHz) to pixel clock (65 MHz for 1024x768)
   // icepll -i 48 -o 65
   SB_PLL40_CORE #(
     .FEEDBACK_PATH("SIMPLE"),
     .DIVR(4'b0010),
     .DIVF(7'b1000000),
     .DIVQ(3'b100),
     .FILTER_RANGE(3'b001),
   ) pll (
     .REFERENCECLK   (clki),
     .PLLOUTCORE     (pixel_clk),
     .BYPASS         (1'b0),
     .RESETB         (1'b1)
   );

   // Video mode constants
   parameter VGA_width         = 1024;
   parameter VGA_height        = 768;
   parameter VGA_h_front_porch = 24;
   parameter VGA_h_sync_width  = 136;
   parameter VGA_h_back_porch  = 160;
   parameter VGA_v_front_porch = 3;
   parameter VGA_v_sync_width  = 6;
   parameter VGA_v_back_porch  = 29;
`endif

`ifdef VGA_MODE_1280x1024
   // PLL: converts system clock (48 MHz) to pixel clock (108 MHz for 1280x1024)
   // icepll -i 48 -o 108
   SB_PLL40_CORE #(
     .FEEDBACK_PATH("SIMPLE"),
     .DIVR(4'b0000),
     .DIVF(7'b0010001),
     .DIVQ(3'b011),
     .FILTER_RANGE(3'b100),
   ) pll (
     .REFERENCECLK   (clki),
     .PLLOUTCORE     (pixel_clk),
     .BYPASS         (1'b0),
     .RESETB         (1'b1)
   );

   // Video mode constants
   parameter VGA_width         = 1280;
   parameter VGA_height        = 1024;
   parameter VGA_h_front_porch = 48;
   parameter VGA_h_sync_width  = 112;
   parameter VGA_h_back_porch  = 248;
   parameter VGA_v_front_porch = 1;
   parameter VGA_v_sync_width  = 3;
   parameter VGA_v_back_porch  = 38;
`endif

   parameter VGA_line_width = VGA_width  + VGA_h_front_porch + VGA_h_sync_width + VGA_h_back_porch;
   parameter VGA_lines      = VGA_height + VGA_v_front_porch + VGA_v_sync_width + VGA_v_back_porch;

   reg [11:0] VGA_X, VGA_Y;  // current pixel coordinates
   reg VGA_hSync, VGA_vSync; // horizontal and vertical synchronization
   reg VGA_DrawArea;         // asserted if current pixel is in drawing area
   reg [15:0] VGA_frame;     // frame counter
   
   always @(posedge pixel_clk) begin
      VGA_DrawArea <= (VGA_X<VGA_width) && (VGA_Y<VGA_height);
      if(VGA_X==VGA_line_width-1) begin
         VGA_X <= 0;
	 if(VGA_Y==VGA_lines-1) begin 
	    VGA_Y <= 0;
	    VGA_frame <= VGA_frame + 1;
	 end else begin
	    VGA_Y <= VGA_Y+1;
	 end
      end else begin
         VGA_X <= VGA_X + 1;
      end
      VGA_hSync <= (VGA_X>=VGA_width+VGA_h_front_porch)  && (VGA_X<VGA_width+VGA_h_front_porch+VGA_h_sync_width);
      VGA_vSync <= (VGA_Y>=VGA_height+VGA_v_front_porch) && (VGA_Y<VGA_height+VGA_v_front_porch+VGA_v_sync_width);
   end

   wire [1:0] out_color;
   wire signed [11:0] dx = $signed(VGA_X) - VGA_width/2;
   wire signed [11:0] dy = $signed(VGA_Y) - VGA_height/2;
   wire signed [15:0] R2 = dx*dx + dy*dy - $signed(VGA_frame << 6);

   assign out_color = VGA_DrawArea ? {R2[12],R2[13]} : 2'b00;

   assign user_1 = VGA_hSync;
   assign user_2 = VGA_vSync;
   assign user_3 = out_color[0];
   assign user_4 = out_color[1];

   // LED driver
   // Note: the LED driver is more intelligent than I wish, it changes color
   // at the same frequency whatever the bit of frame I'm using, I need to 
   // understand what's going on here (supposed to be a PWM, maybe I should
   // generate pulses of varying length to control intensity of r,g,b...)

   SB_RGBA_DRV #(
    .CURRENT_MODE("0b1"),       // half current mode 
    .RGB0_CURRENT("0b001111"),  // Blue - Needs more current.
    .RGB1_CURRENT("0b000011"),  // Red
    .RGB2_CURRENT("0b000011")   // Green
   ) led_driver (
    .CURREN(1'b1),
    .RGBLEDEN(1'b1),
    .RGB0PWM(VGA_frame[3]), // red
    .RGB1PWM(VGA_frame[4]), // green			   
    .RGB2PWM(VGA_frame[5]), // blue  
    .RGB0(rgb0),
    .RGB1(rgb1),
    .RGB2(rgb2)
   );

endmodule
