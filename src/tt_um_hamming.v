/*
 * tt_um_hamming.v — Codificador/Decodificador Hamming(12,8) SEC-DED
 *                   para Tiny Tapeout
 *
 * Hamming(12,8): 8 bits de datos → 12 bits de codeword
 * + 1 bit de paridad global para SEC-DED (13 bits en total)
 *
 * SEC = Single Error Correcting  (corrige errores de 1 bit)
 * DED = Double Error Detecting   (detecta errores de 2 bits)
 *
 * Lógica puramente combinacional — clk/rst_n presentes por requerimiento
 * del template de Tiny Tapeout pero no utilizados en la lógica.
 *
 * ┌──────────┬─────────────────────────────────────────────────────────┐
 * │  ui_in   │ [7:0]  ENCODE: data[7:0]       DECODE: received[7:0]   │
 * │  uo_out  │ [7:0]  ENCODE: codeword[7:0]   DECODE: data corregido  │
 * ├──────────┼──────────────────────────────────────────────────────── │
 * │  uio[0]  │ INPUT  mode: 0 = encode, 1 = decode                    │
 * │  uio[1]  │ BIDIR  ENCODE(out): paridad global  DECODE(in): recv[12]│
 * │  uio[5:2]│ BIDIR  ENCODE(out): codeword[11:8]  DECODE(in): recv[11:8]│
 * │  uio[6]  │ OUTPUT error_corrected — se corrigió 1 bit              │
 * │  uio[7]  │ OUTPUT error_detected  — error doble, NO corregible     │
 * └──────────┴─────────────────────────────────────────────────────────┘
 *
 * Mapa del codeword (posición Hamming 1-indexed → índice de bit):
 *   pos  1 → codeword[0]  = p1      (paridad)
 *   pos  2 → codeword[1]  = p2      (paridad)
 *   pos  3 → codeword[2]  = data[0]
 *   pos  4 → codeword[3]  = p4      (paridad)
 *   pos  5 → codeword[4]  = data[1]
 *   pos  6 → codeword[5]  = data[2]
 *   pos  7 → codeword[6]  = data[3]
 *   pos  8 → codeword[7]  = p8      (paridad)
 *   pos  9 → codeword[8]  = data[4]
 *   pos 10 → codeword[9]  = data[5]
 *   pos 11 → codeword[10] = data[6]
 *   pos 12 → codeword[11] = data[7]
 *   extra  → codeword[12] = paridad global (XOR de todos los anteriores)
 *
 * Ejemplo encode:
 *   ui_in = 8'hA5, uio[0] = 0
 *   → uo_out = codeword[7:0], uio[5:2] = codeword[11:8], uio[1] = paridad global
 *
 * Ejemplo decode (con posible error):
 *   ui_in = received[7:0], uio[5:2] = received[11:8], uio[1] = received[12], uio[0] = 1
 *   → uo_out = data corregido, uio[6] = error_corrected, uio[7] = error_detected
 */

module tt_um_hamming (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire mode = uio_in[0];  // 0 = encode, 1 = decode

    // ----------------------------------------------------------------
    // ENCODER — Hamming(12,8)
    // ----------------------------------------------------------------
    wire [7:0] data = ui_in;

    // Bits de paridad (paridad par: XOR de todas las posiciones que cubre)
    // p1 cubre posiciones con bit0=1: 1,3,5,7,9,11  → data[0,1,3,4,6]
    // p2 cubre posiciones con bit1=1: 2,3,6,7,10,11 → data[0,2,3,5,6]
    // p4 cubre posiciones con bit2=1: 4,5,6,7,12    → data[1,2,3,7]
    // p8 cubre posiciones con bit3=1: 8,9,10,11,12  → data[4,5,6,7]
    wire p1 = data[0] ^ data[1] ^ data[3] ^ data[4] ^ data[6];
    wire p2 = data[0] ^ data[2] ^ data[3] ^ data[5] ^ data[6];
    wire p4 = data[1] ^ data[2] ^ data[3] ^ data[7];
    wire p8 = data[4] ^ data[5] ^ data[6] ^ data[7];

    wire [11:0] codeword;
    assign codeword[0]  = p1;
    assign codeword[1]  = p2;
    assign codeword[2]  = data[0];
    assign codeword[3]  = p4;
    assign codeword[4]  = data[1];
    assign codeword[5]  = data[2];
    assign codeword[6]  = data[3];
    assign codeword[7]  = p8;
    assign codeword[8]  = data[4];
    assign codeword[9]  = data[5];
    assign codeword[10] = data[6];
    assign codeword[11] = data[7];

    // Paridad global para SEC-DED: XOR de los 12 bits del codeword
    wire p_overall = ^codeword;

    // ----------------------------------------------------------------
    // DECODER — Síndrome y corrección
    // ----------------------------------------------------------------
    // Ensamblar palabra recibida (13 bits)
    wire [12:0] received;
    assign received[7:0]  = ui_in;
    assign received[11:8] = uio_in[5:2];
    assign received[12]   = uio_in[1];   // paridad global recibida

    // Re-calcular bits de paridad sobre los bits recibidos → síndrome
    wire s1 = received[0]^received[2]^received[4]^received[6]^received[8]^received[10];
    wire s2 = received[1]^received[2]^received[5]^received[6]^received[9]^received[10];
    wire s4 = received[3]^received[4]^received[5]^received[6]^received[11];
    wire s8 = received[7]^received[8]^received[9]^received[10]^received[11];

    wire [3:0] syndrome = {s8, s4, s2, s1};

    // Verificación de paridad global: XOR de los 13 bits recibidos
    // Si no hay error → 0
    // Si hay error 1 bit → 1  (corregible)
    // Si hay error 2 bits → 0 con syndrome≠0 (detectable, no corregible)
    wire p_check = ^received;

    wire single_error = (syndrome != 4'd0) &&  p_check;  // SEC
    wire double_error = (syndrome != 4'd0) && !p_check;  // DED

    // Corrección: el síndrome indica la posición (1-indexed) del bit erróneo
    wire [11:0] corrected;
    genvar i;
    generate
        for (i = 0; i < 12; i = i + 1) begin : g_correct
            assign corrected[i] = (single_error && (syndrome == (i + 1))) ?
                                   ~received[i] : received[i];
        end
    endgenerate

    // Extraer datos del codeword corregido (posiciones de datos en el codeword)
    wire [7:0] decoded;
    assign decoded[0] = corrected[2];    // pos  3
    assign decoded[1] = corrected[4];    // pos  5
    assign decoded[2] = corrected[5];    // pos  6
    assign decoded[3] = corrected[6];    // pos  7
    assign decoded[4] = corrected[8];    // pos  9
    assign decoded[5] = corrected[9];    // pos 10
    assign decoded[6] = corrected[10];   // pos 11
    assign decoded[7] = corrected[11];   // pos 12

    // ----------------------------------------------------------------
    // Salidas
    // ----------------------------------------------------------------
    // uo_out: codeword[7:0] en encode, data corregido en decode
    assign uo_out = mode ? decoded : codeword[7:0];

    // uio_out:
    //   encode → [1]=p_overall, [5:2]=codeword[11:8], [7:6]=0
    //   decode → [6]=single_error, [7]=double_error, resto don't care
    assign uio_out = mode ?
        {double_error, single_error, 6'b000000} :
        {2'b00, codeword[11:8], p_overall, 1'b0};
    //   [7:6]  [5:2]            [1]        [0]

    // uio_oe:
    //   encode → [7:1] outputs, [0] input (mode)    → 8'b11111110
    //   decode → [7:6] outputs (error flags),
    //            [5:0] inputs (codeword + mode)       → 8'b11000000
    assign uio_oe = mode ? 8'b11000000 : 8'b11111110;

endmodule
