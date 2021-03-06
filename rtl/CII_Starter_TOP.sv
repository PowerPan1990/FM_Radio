/* FPGA top level
 *
 * KEY[0]           external reset
 * SW[9]            apply 1 kHz test tone to DAC
 * SW[5:3, 1:0]     select fixed frequency defined in 'freq_select'
 * EXT_CLOCK, SW[2] differential input for antenna signal
 */

module CII_Starter_TOP
  (/* Clock Input */
   input  wire [1:0]  CLOCK_24,    // 24 MHz
   input  wire [1:0]  CLOCK_27,    // 27 MHz
   input  wire        CLOCK_50,    // 50 MHz
   input  wire        EXT_CLOCK,   // External Clock

   /* Push Button */
   input  wire [3:0]  KEY,         // Pushbutton[3:0]

   /* DPDT Switch */
   input wire  [9:0]  SW,          // Toggle Switch[9:0]

   /* 7-SEG Display */
   output wire [6:0]  HEX0,        // Seven Segment Digit 0
   output wire [6:0]  HEX1,        // Seven Segment Digit 1
   output wire [6:0]  HEX2,        // Seven Segment Digit 2
   output wire [6:0]  HEX3,        // Seven Segment Digit 3

   /* LED */
   output wire [7:0]  LEDG,        // LED Green[7:0]
   output wire [9:0]  LEDR,        // LED Red[9:0]

   /* UART */
   output wire        UART_TXD,    // UART Transmitter
   input  wire        UART_RXD,    // UART Receiver

   /* SDRAM Interface */
   inout  wire [15:0] DRAM_DQ,     // SDRAM Data bus 16 Bits
   output wire [11:0] DRAM_ADDR,   // SDRAM Address bus 12 Bits
   output wire        DRAM_LDQM,   // SDRAM Low-byte Data Mask
   output wire        DRAM_UDQM,   // SDRAM High-byte Data Mask
   output wire        DRAM_WE_N,   // SDRAM Write Enable
   output wire        DRAM_CAS_N,  // SDRAM Column Address Strobe
   output wire        DRAM_RAS_N,  // SDRAM Row Address Strobe
   output wire        DRAM_CS_N,   // SDRAM Chip Select
   output wire        DRAM_BA_0,   // SDRAM Bank Address 0
   output wire        DRAM_BA_1,   // SDRAM Bank Address 0
   output wire        DRAM_CLK,    // SDRAM Clock
   output wire        DRAM_CKE,    // SDRAM Clock Enable

   /* Flash Interface */
   inout  wire [7:0]  FL_DQ,       // FLASH Data bus 8 Bits
   output wire [21:0] FL_ADDR,     // FLASH Address bus 22 Bits
   output wire        FL_WE_N,     // FLASH Write Enable
   output wire        FL_RST_N,    // FLASH Reset
   output wire        FL_OE_N,     // FLASH Output Enable
   output wire        FL_CE_N,     // FLASH Chip Enable

   /* SRAMwire  Interface */
   inout  wire [15:0] SRAM_DQ,     // SRAM Data bus 16 Bits
   output wire [17:0] SRAM_ADDR,   // SRAM Address bus 18 Bits
   output wire        SRAM_UB_N,   // SRAM High-byte Data Mask
   output wire        SRAM_LB_N,   // SRAM Low-byte Data Mask
   output wire        SRAM_WE_N,   // SRAM Write Enable
   output wire        SRAM_CE_N,   // SRAM Chip Enable
   output wire        SRAM_OE_N,   // SRAM Output Enable

   /* SD Card Interface */
   inout  wire        SD_DAT,      // SD Card Data
   inout  wire        SD_DAT3,     // SD Card Data 3
   inout  wire        SD_CMD,      // SD Card Command Signal
   output wire        SD_CLK,      // SD Card Clock

   /* I2C */
   inout  wire        I2C_SDAT,    // I2C Data
   inout  wire        I2C_SCLK,    // I2C Clock

   /* PS2 */
   input  wire        PS2_DAT,     // PS2 Data
   input  wire        PS2_CLK,     // PS2 Clock

   /* USB JTAG link */
   input  wire        TDI,         // CPLD -> FPGA (data in)
   input  wire        TCK,         // CPLD -> FPGA (clk)
   input  wire        TCS,         // CPLD -> FPGA (CS)
   output wire        TDO,         // FPGA -> CPLD (data out)

   /* VGA */
   output wire        VGA_HS,      // VGA H_SYNC
   output wire        VGA_VS,      // VGA V_SYNC
   output wire [3:0]  VGA_R,       // VGA Red[3:0]
   output wire [3:0]  VGA_G,       // VGA Green[3:0]
   output wire [3:0]  VGA_B,       // VGA Blue[3:0]

   /* Audio CODEC */
   inout  wire        AUD_ADCLRCK, // Audio CODEC ADC LR Clock
   input  wire        AUD_ADCDAT,  // Audio CODEC ADC Data
   inout  wire        AUD_DACLRCK, // Audio CODEC DAC LR Clock
   output wire        AUD_DACDAT,  // Audio CODEC DAC Data
   inout  wire        AUD_BCLK,    // Audio CODEC Bit-Stream Clock
   output wire        AUD_XCK,     // Audio CODEC Chip Clock

   /* GPIO */
   inout  wire [35:0] GPIO_0);     // GPIO Connection 0

   localparam width_dds = 32;

   wire                     reset_in;               // power-on reset
   wire                     reset_sync;             // synchronized reset
   wire                     clk240m;                // 240 MHz clock
   wire                     en48m;                  //  48 MHz clock enable
   wire                     en1m6;                  // 1.6 MHz clock enable
   wire                     en960k;                 // 960 kHz clock enable
   wire                     en32k;                  //  32 kHz clock enable
   wire [width_dds - 1 : 0] K;                      // DDS phase reload constant
   wire [15:0]              audio_dat;              // audio data
   wire [15:0]              radio_core_demodulated; // radio_core demodulated audio data
   wire [15:0]              test_tone_data;         // 1 kHz test tone audio data
   wire                     i2c_scl, i2c_sda;       // I2C interface

   /* open-drain outputs for I2C */
   assign I2C_SCLK = (i2c_scl) ? 1'bz : 1'b0;
   assign I2C_SDAT = (i2c_sda) ? 1'bz : 1'b0;

   assign reset_in = ~KEY[0];

   assign audio_dat = (SW[9]) ? test_tone_data : radio_core_demodulated;

   assign AUD_ADCLRCK = 1'b0;

   pll inst_pll
     (.inclk0(CLOCK_24[0]),
      .c0    (clk240m));

   cru inst_cru
     (.reset_in,
      .reset_sync,
      .clk240m,
      .en48m,
      .en1m6,
      .en960k,
      .en32k);

   radio_core
     #(.width_dds   (width_dds),
       .width_cordic(17),
       .R1          (250),
       .R2          (30))
   inst_radio_core
     (.reset        (reset_sync),
      .clk          (clk240m),
      .en48m,
      .en960k,
      .en32k,
      .adc          (EXT_CLOCK),
      .K,
      .demodulated  (radio_core_demodulated));

   freq_select
     #(.width_dds(width_dds))
   inst_freq_select
     (.SW,
      .HEX({HEX3, HEX2, HEX1, HEX0}),
      .K);

   wm8731_controller inst_wm8731_controller
     (.reset(reset_sync),
      .clk       (clk240m),
      .en48m,
      .en1m6,
      .en32k,
      .audio_dat,
      .i2c_scl,
      .i2c_sda,
      .dac_lr_ck(AUD_DACLRCK),
      .dac_dat  (AUD_DACDAT),
      .bclk     (AUD_BCLK),
      .mclk     (AUD_XCK));

   test_tone inst_test_tone
     (.reset(reset_sync),
      .clk  (clk240m),
      .en   (en32k),
      .data (test_tone_data));
endmodule
