`default_nettype none
`timescale 1ns / 1ps

// ============================================================
// Modulo 7 segmentos HEX de 3 digitos
// value[11:8] = digito izquierdo
// value[7:4]  = digito central
// value[3:0]  = digito derecho
//
// an y seg son activos en 0.
// dp activo en 0, pero aqui se deja apagado en 1.
// ============================================================

module seg7_hex3 #(
    parameter int CLK_HZ = 16_000_000,
    parameter int REFRESH_PER_DIGIT_HZ = 1000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] value,
    output reg  [2:0]  an,
    output reg  [6:0]  seg,
    output reg         dp
);

    // Para 3 digitos:
    // TICKS_PER_DIGIT = ciclos de clock que dura activo cada digito
    localparam int TICKS_PER_DIGIT = CLK_HZ / (REFRESH_PER_DIGIT_HZ * 3);
    localparam int CNT_W = (TICKS_PER_DIGIT <= 1) ? 1 : $clog2(TICKS_PER_DIGIT);

    reg [CNT_W-1:0] tick_cnt;
    reg [1:0]       sel;

    // Divisor de refresco y selector de digito
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_cnt <= '0;
            sel      <= 2'd0;
        end else begin
            if (tick_cnt == TICKS_PER_DIGIT - 1) begin
                tick_cnt <= '0;

                if (sel == 2'd2)
                    sel <= 2'd0;
                else
                    sel <= sel + 2'd1;

            end else begin
                tick_cnt <= tick_cnt + 1'b1;
            end
        end
    end

    // Separacion de nibbles
    wire [3:0] nibble_d0 = value[3:0];    // derecha
    wire [3:0] nibble_d1 = value[7:4];    // centro
    wire [3:0] nibble_d2 = value[11:8];   // izquierda

    reg [3:0] nibble;

    // Multiplexado de los 3 anodos
    always_comb begin
        an     = 3'b111;
        nibble = 4'h0;

        unique case (sel)
            2'd0: begin
                an     = 3'b110;   // digito derecho activo
                nibble = nibble_d0;
            end

            2'd1: begin
                an     = 3'b101;   // digito central activo
                nibble = nibble_d1;
            end

            2'd2: begin
                an     = 3'b011;   // digito izquierdo activo
                nibble = nibble_d2;
            end

            default: begin
                an     = 3'b111;
                nibble = 4'h0;
            end
        endcase
    end

    // Decoder HEX a 7 segmentos
    // Orden: seg[6:0] = a b c d e f g
    // Activo en bajo
    always_comb begin
        dp = 1'b1;   // punto decimal apagado

        unique case (nibble)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end

endmodule