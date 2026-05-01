/*
 * tt_um_uart.v — UART 8N1 para Tiny Tapeout
 *
 * Formato: 8 bits de datos, sin paridad, 1 stop bit (8N1)
 *
 * ┌──────────┬─────────────────────────────────────────────┐
 * │  ui_in   │ [7:0]  Byte a transmitir                    │
 * │  uo_out  │ [7:0]  Último byte recibido                 │
 * ├──────────┼─────────────────────────────────────────────┤
 * │  uio[0]  │ INPUT  tx_valid  — flanco alto dispara TX   │
 * │  uio[1]  │ OUTPUT tx_busy   — 1 mientras transmite     │
 * │  uio[2]  │ OUTPUT rx_valid  — pulso 1 ciclo al recibir │
 * │  uio[3]  │ OUTPUT TX        — línea serie de salida    │
 * │  uio[4]  │ INPUT  RX        — línea serie de entrada   │
 * │  uio[5]  │ OUTPUT rx_error  — framing error            │
 * │  uio[6]  │ INPUT  (sin uso)                            │
 * │  uio[7]  │ INPUT  (sin uso)                            │
 * └──────────┴─────────────────────────────────────────────┘
 *
 * Parámetros:
 *   CLK_FREQ  — frecuencia del reloj en Hz  (default 50 MHz)
 *   BAUD_RATE — velocidad de transmisión    (default 115200)
 *
 * Ejemplo de uso:
 *   Conectar uio[3] (TX) y uio[4] (RX) a un adaptador USB-serial.
 *   Poner dato en ui_in, dar pulso en uio[0].
 *   Leer uo_out cuando uio[2] suba.
 */

module tt_um_uart #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ----------------------------------------------------------------
    // Constantes
    // ----------------------------------------------------------------
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CTR_BITS     = $clog2(CLKS_PER_BIT) + 1;

    // ----------------------------------------------------------------
    // Señales I/O
    // ----------------------------------------------------------------
    wire tx_valid_raw = uio_in[0];
    wire rx_pin_raw   = uio_in[4];

    reg  tx_busy, tx_out;
    reg  rx_valid, rx_error;
    reg  [7:0] rx_data;

    assign uo_out  = rx_data;
    //                         [7:6]   [5]       [4]    [3]    [2]       [1]      [0]
    assign uio_out = {2'b00, rx_error, 1'b0, tx_out, rx_valid, tx_busy, 1'b0};
    assign uio_oe  = 8'b00101110; // outputs: [5,3,2,1] | inputs: [7,6,4,0]

    // ----------------------------------------------------------------
    // TX — transmisor
    // ----------------------------------------------------------------
    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    reg  [1:0]          tx_state;
    reg  [CTR_BITS-1:0] tx_cnt;
    reg  [7:0]          tx_data_reg;
    reg  [2:0]          tx_bit;
    reg                 tx_valid_r;

    // Disparo por flanco de subida en tx_valid (mientras no esté ocupado)
    wire tx_start = tx_valid_raw & ~tx_valid_r & ~tx_busy;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) tx_valid_r <= 1'b0;
        else        tx_valid_r <= tx_valid_raw;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state    <= TX_IDLE;
            tx_out      <= 1'b1;
            tx_busy     <= 1'b0;
            tx_cnt      <= 0;
            tx_data_reg <= 8'h00;
            tx_bit      <= 3'd0;
        end else begin
            case (tx_state)

                TX_IDLE: begin
                    tx_out  <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_data_reg <= ui_in;
                        tx_busy     <= 1'b1;
                        tx_out      <= 1'b0;          // start bit (bajo)
                        tx_cnt      <= CLKS_PER_BIT - 1;
                        tx_state    <= TX_START;
                    end
                end

                TX_START: begin
                    if (tx_cnt == 0) begin
                        tx_out   <= tx_data_reg[0];   // bit 0 (LSB primero)
                        tx_bit   <= 3'd0;
                        tx_cnt   <= CLKS_PER_BIT - 1;
                        tx_state <= TX_DATA;
                    end else
                        tx_cnt <= tx_cnt - 1;
                end

                TX_DATA: begin
                    if (tx_cnt == 0) begin
                        if (tx_bit == 3'd7) begin
                            tx_out   <= 1'b1;         // stop bit (alto)
                            tx_cnt   <= CLKS_PER_BIT - 1;
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit <= tx_bit + 1;
                            tx_out <= tx_data_reg[tx_bit + 1]; // siguiente bit
                            tx_cnt <= CLKS_PER_BIT - 1;
                        end
                    end else
                        tx_cnt <= tx_cnt - 1;
                end

                TX_STOP: begin
                    if (tx_cnt == 0) begin
                        tx_busy  <= 1'b0;
                        tx_state <= TX_IDLE;
                    end else
                        tx_cnt <= tx_cnt - 1;
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // RX — receptor
    // ----------------------------------------------------------------
    // Sincronizador de 2 flip-flops para cruzar dominio asíncrono
    reg rx_s1, rx_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_s1 <= 1'b1; rx_s2 <= 1'b1; end
        else        begin rx_s1 <= rx_pin_raw; rx_s2 <= rx_s1; end
    end

    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    reg  [1:0]          rx_state;
    reg  [CTR_BITS-1:0] rx_cnt;
    reg  [7:0]          rx_shift;
    reg  [2:0]          rx_bit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_cnt   <= 0;
            rx_shift <= 8'h00;
            rx_data  <= 8'h00;
            rx_valid <= 1'b0;
            rx_error <= 1'b0;
            rx_bit   <= 3'd0;
        end else begin
            rx_valid <= 1'b0;    // pulso de 1 ciclo

            case (rx_state)

                RX_IDLE: begin
                    // Detectar inicio de start bit (línea baja)
                    if (!rx_s2) begin
                        rx_cnt   <= CLKS_PER_BIT/2 - 1; // ir al centro del bit
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (rx_cnt == 0) begin
                        if (!rx_s2) begin              // confirmar start válido
                            rx_bit   <= 3'd0;
                            rx_cnt   <= CLKS_PER_BIT - 1;
                            rx_state <= RX_DATA;
                        end else
                            rx_state <= RX_IDLE;       // falso start, ignorar
                    end else
                        rx_cnt <= rx_cnt - 1;
                end

                RX_DATA: begin
                    if (rx_cnt == 0) begin
                        rx_shift[rx_bit] <= rx_s2;     // muestrear bit
                        rx_cnt <= CLKS_PER_BIT - 1;
                        if (rx_bit == 3'd7) begin
                            rx_state <= RX_STOP;
                        end else
                            rx_bit <= rx_bit + 1;
                    end else
                        rx_cnt <= rx_cnt - 1;
                end

                RX_STOP: begin
                    if (rx_cnt == 0) begin
                        rx_data  <= rx_shift;
                        rx_valid <= 1'b1;
                        rx_error <= ~rx_s2;            // framing error: stop debe ser alto
                        rx_state <= RX_IDLE;
                    end else
                        rx_cnt <= rx_cnt - 1;
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule
