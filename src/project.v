/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
 
`default_nettype none
 
module tt_um_DlynchR_spi_display (
    input  wire [7:0] ui_in,    // Dedicated inputs  -> tx_data[7:0]
    output wire [7:0] uo_out,   // Dedicated outputs -> {dp, seg[6:0]}
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // -----------------------------------------------------------------------
    // Mapeo de pines (ver info.yaml):
    //   ui_in[7:0] = tx_data (byte que el slave envía por MISO)
    //   uo_out[6:0] = seg[6:0]  (7 segmentos, activos en bajo)
    //   uo_out[7]   = dp        (punto decimal, activo en bajo)
    //   uio[0] = sck      (in)
    //   uio[1] = cs_n     (in)
    //   uio[2] = mosi     (in)
    //   uio[3] = miso     (out)
    //   uio[4] = rx_valid (out)
    //   uio[5] = an[0]    (out, activo bajo, dígito derecho)
    //   uio[6] = an[1]    (out, activo bajo, dígito central)
    //   uio[7] = an[2]    (out, activo bajo, dígito izquierdo)
    // -----------------------------------------------------------------------

    // Parámetros de refresco del 7-seg
    // Para simulación rápida usar -DSIM_FAST_REFRESH (ver Makefile RTL).
`ifdef SIM_FAST_REFRESH
    localparam CLK_HZ_PARAM    = 12000;
    localparam REFRESH_HZ_PARAM = 1000;   // -> TICKS_PER_DIGIT = 4
`else
    localparam CLK_HZ_PARAM    = 16000000;
    localparam REFRESH_HZ_PARAM = 1000;
`endif

    wire        sck      = uio_in[0];
    wire        cs_n     = uio_in[1];
    wire        mosi     = uio_in[2];
    wire        miso;
    wire        rx_valid;
    wire [7:0]  rx_data;

    wire [2:0]  an;
    wire [6:0]  seg;
    wire        dp;

    // Dirección de los uio: bits 3..7 son salidas
    assign uio_oe       = 8'b1111_1000;
    assign uio_out[2:0] = 3'b000;
    assign uio_out[3]   = miso;
    assign uio_out[4]   = rx_valid;
    assign uio_out[5]   = an[0];
    assign uio_out[6]   = an[1];
    assign uio_out[7]   = an[2];

    // Salidas dedicadas: 7 segmentos + punto decimal
    assign uo_out[6:0] = seg;
    assign uo_out[7]   = dp;

    // Esclavo SPI (Modo 0)
    spi_slave #(
        .CPOL(0),
        .CPHA(0)
    ) u_spi_slave (
        .clk      (clk),
        .rst_n    (rst_n),
        .sck      (sck),
        .cs_n     (cs_n),
        .mosi     (mosi),
        .miso     (miso),
        .tx_data  (ui_in),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    // Display de 3 dígitos hex. Sólo usamos los 8 bits bajos del valor;
    // el dígito izquierdo queda siempre en 0.
    seg7_hex3 #(
        .CLK_HZ              (CLK_HZ_PARAM),
        .REFRESH_PER_DIGIT_HZ(REFRESH_HZ_PARAM)
    ) u_seg7 (
        .clk   (clk),
        .rst   (~rst_n),
        .value ({4'h0, rx_data}),
        .an    (an),
        .seg   (seg),
        .dp    (dp)
    );

    // Entradas no usadas (evita warnings del linter)
    wire _unused = &{ena, 1'b0};

endmodule