/*
 * tt_tiny_spi.v — Tiny Tapeout wrapper for tiny_spi
 *
 * Adaptado de OpenCores tiny_spi (Thomas Chou, LGPL)
 * para cumplir con la interfaz estándar de Tiny Tapeout.
 *
 * ┌─────────────────────────────────────────────────────┐
 * │  Pin Map                                            │
 * ├──────────┬────────────────────────────────────────  │
 * │  ui_in   │ [7:0]  Byte a transmitir por SPI         │
 * │  uo_out  │ [7:0]  Último byte recibido (MISO)       │
 * ├──────────┼───────────────────────────────────────── │
 * │  uio[0]  │ INPUT  start — flanco de subida = enviar │
 * │  uio[1]  │ OUTPUT busy  — 1 mientras transfiere     │
 * │  uio[2]  │ OUTPUT tx_ready — 1 cuando listo         │
 * │  uio[3]  │ OUTPUT MOSI                              │
 * │  uio[4]  │ OUTPUT SCLK                              │
 * │  uio[5]  │ OUTPUT CS_N (activo bajo)                │
 * │  uio[6]  │ INPUT  MISO                              │
 * │  uio[7]  │ INPUT  (sin uso)                         │
 * └──────────┴─────────────────────────────────────────-┘
 *
 * Parámetros:
 *   BAUD_DIV  — SCLK = clk / (2 * BAUD_DIV), default 8
 *   SPI_MODE  — 0..3 (CPOL/CPHA), default 0
 */

module tt_um_tiny_spi #(
    parameter BAUD_DIV = 8,   // SCLK = clk / (2*BAUD_DIV)
    parameter SPI_MODE = 0    // 0=modo0, 1=modo1, 2=modo2, 3=modo3
)(
    input  wire [7:0] ui_in,   // dato a transmitir
    output wire [7:0] uo_out,  // dato recibido
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,     // requerido por Tiny Tapeout (no usado)
    input  wire       clk,
    input  wire       rst_n    // reset activo bajo (estándar TT)
);

    // ----------------------------------------------------------------
    // Constantes de configuración
    // ----------------------------------------------------------------
    localparam DIV_VAL  = BAUD_DIV - 1;               // valor de recarga
    localparam DIV_BITS = $clog2(BAUD_DIV) + 1;       // bits del contador

    wire cpol = (SPI_MODE == 2) || (SPI_MODE == 3);
    wire cpha = (SPI_MODE == 1) || (SPI_MODE == 3);

    // ----------------------------------------------------------------
    // Señales de I/O
    // ----------------------------------------------------------------
    wire rst   = ~rst_n;
    wire start = uio_in[0];
    wire miso  = uio_in[6];

    // Detección de flanco de subida en 'start'
    reg start_r;
    always @(posedge clk or posedge rst)
        if (rst) start_r <= 1'b0;
        else     start_r <= start;

    wire wstb = start & ~start_r;   // pulso de 1 ciclo al subir 'start'

    // ----------------------------------------------------------------
    // Registros internos (igual que tiny_spi original)
    // ----------------------------------------------------------------
    reg [7:0]           sr8;    // shift register
    reg [7:0]           bb8;    // buffer register
    reg                 bba;    // buffer disponible
    reg [2:0]           bc, bc_next;
    reg [DIV_BITS-1:0]  cc, cc_next;
    reg                 sck_next; // valor combinacional
    reg                 sck_reg;  // registrado — sin glitches en SCLK
    reg                 sf, ld;

    localparam IDLE   = 2'd0;
    localparam PHASE1 = 2'd1;
    localparam PHASE2 = 2'd2;

    reg [1:0] spi_seq, spi_seq_next;

    // Registro de SCLK para evitar glitches en la salida
    always @(posedge clk or posedge rst) begin
        if (rst) sck_reg <= cpol;
        else     sck_reg <= sck_next;
    end

    // ----------------------------------------------------------------
    // Buffer de transmisión
    // ----------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            bb8 <= 8'h00;
            bba <= 1'b0;
        end else begin
            if (wstb) begin
                bb8 <= ui_in;
                bba <= 1'b1;
            end else if (ld) begin
                bb8 <= (spi_seq == IDLE) ? sr8 : {sr8[6:0], miso};
                bba <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Shift register
    // ----------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst)    sr8 <= 8'h00;
        else if (ld) sr8 <= bb8;
        else if (sf) sr8 <= {sr8[6:0], miso};
    end

    // ----------------------------------------------------------------
    // Máquina de estados — secuencial
    // ----------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_seq <= IDLE;
            cc      <= {DIV_BITS{1'b0}};
            bc      <= 3'd0;
        end else begin
            spi_seq <= spi_seq_next;
            cc      <= cc_next;
            bc      <= bc_next;
        end
    end

    // ----------------------------------------------------------------
    // Máquina de estados — combinacional (lógica de tiny_spi original)
    // ----------------------------------------------------------------
    always @(*) begin
        sck_next     = cpol;
        cc_next      = DIV_VAL[DIV_BITS-1:0];
        bc_next      = bc;
        ld           = 1'b0;
        sf           = 1'b0;
        spi_seq_next = spi_seq;

        case (spi_seq)
            IDLE: begin
                if (bba) begin
                    bc_next      = 3'd7;
                    ld           = 1'b1;
                    spi_seq_next = PHASE2;
                end
            end

            PHASE2: begin
                sck_next = cpol ^ cpha;
                if (cc == 0)
                    spi_seq_next = PHASE1;
                else begin
                    cc_next      = cc - 1'b1;
                    spi_seq_next = PHASE2;
                end
            end

            PHASE1: begin
                sck_next = ~(cpol ^ cpha);
                if (cc == 0) begin
                    bc_next = bc - 3'd1;
                    sf      = 1'b1;
                    if (bc == 3'd0) begin
                        if (bba) begin
                            bc_next      = 3'd7;
                            ld           = 1'b1;
                            spi_seq_next = PHASE2;
                        end else
                            spi_seq_next = IDLE;
                    end else
                        spi_seq_next = PHASE2;
                end else begin
                    cc_next      = cc - 1'b1;
                    spi_seq_next = PHASE1;
                end
            end

            default: spi_seq_next = IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Salidas
    // ----------------------------------------------------------------
    wire busy = (spi_seq != IDLE);
    wire txr  = ~bba;          // listo para nuevo byte
    wire cs_n = ~busy;         // CS activo mientras transfiere

    assign uo_out = sr8;

    // uio_out: [0]=don't care, [1]=busy, [2]=txr, [3]=MOSI, [4]=SCLK, [5]=CS_N
    assign uio_out = {2'b00, cs_n, sck_reg, sr8[7], txr, busy, 1'b0};
    //                [7:6]  [5]    [4]      [3]     [2]  [1]   [0]

    // [0]=input, [1..5]=output, [6]=input, [7]=input
    assign uio_oe  = 8'b00111110;

endmodule // tt_um_tiny_spi
