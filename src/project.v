/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
 
`default_nettype none
 
module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs  -> tx_data[7:0]
    output wire [7:0] uo_out,   // Dedicated outputs -> rx_data[7:0]
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // -----------------------------------------------------------------------
    // Mapeo de pines (ver info.yaml):
    //   uio[0] = sck      (in)
    //   uio[1] = cs_n     (in)
    //   uio[2] = mosi     (in)
    //   uio[3] = miso     (out)
    //   uio[4] = rx_valid (out)
    // -----------------------------------------------------------------------
    wire        sck      = uio_in[0];
    wire        cs_n     = uio_in[1];
    wire        mosi     = uio_in[2];
    wire        miso;
    wire        rx_valid;
    wire [7:0]  rx_data;

    // Dirección de los uio: salidas en bits 3 y 4, resto entradas
    assign uio_oe       = 8'b0001_1000;
    assign uio_out[2:0] = 3'b000;
    assign uio_out[3]   = miso;
    assign uio_out[4]   = rx_valid;
    assign uio_out[7:5] = 3'b000;

    // Salida paralela: byte recibido por SPI
    assign uo_out = rx_data;

    // Instancia del esclavo SPI (modo 0 por defecto)
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

    // Entradas no usadas (evita warnings del linter)
    wire _unused = &{ena, uio_in[7:3], 1'b0};

endmodule