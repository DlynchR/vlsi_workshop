// =============================================================================
// spi_slave.sv — Interfaz SPI Subordinado (Slave)
// Compatible con los 4 modos SPI (CPOL/CPHA)
// Descripción:
//   - Recibe y transmite 8 bits por transacción SPI
//   - CPOL y CPHA configurables vía parámetros
//   - Registra el byte recibido en rx_data cuando la transacción completa
//   - tx_data cargado en paralelo antes de cs_n bajo
//   - Señal rx_valid pulsa 1 ciclo al completar recepción
// =============================================================================

module spi_slave #(
    parameter CPOL = 0,   // Polaridad del reloj: 0 = inactivo en bajo, 1 = inactivo en alto
    parameter CPHA = 0    // Fase del reloj:      0 = muestra en primer flanco, 1 = en segundo
) (
    // Señales del sistema
    input  logic       clk,       // Reloj del sistema (para sincronización)
    input  logic       rst_n,     // Reset activo en bajo

    // Puerto SPI
    input  logic       sck,       // SPI Clock del maestro
    input  logic       cs_n,      // Chip Select activo en bajo
    input  logic       mosi,      // Master Out Slave In
    output logic       miso,      // Master In Slave Out

    // Interfaz paralela interna
    input  logic [7:0] tx_data,   // Dato a transmitir (cargar antes de cs_n bajo)
    output logic [7:0] rx_data,   // Dato recibido (válido cuando rx_valid = 1)
    output logic       rx_valid   // Pulso 1 ciclo: byte recibido completo
);

    // -------------------------------------------------------------------------
    // Sincronización de señales SPI al dominio de reloj del sistema
    // (doble FF para evitar metaestabilidad)
    // -------------------------------------------------------------------------
    logic sck_r0,  sck_r1,  sck_r2;
    logic cs_n_r0, cs_n_r1;
    logic mosi_r0, mosi_r1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {sck_r0,  sck_r1,  sck_r2} <= 3'b000;
            {cs_n_r0, cs_n_r1}         <= 2'b11;
            {mosi_r0, mosi_r1}         <= 2'b00;
        end else begin
            sck_r0  <= sck;   sck_r1  <= sck_r0;  sck_r2 <= sck_r1;
            cs_n_r0 <= cs_n;  cs_n_r1 <= cs_n_r0;
            mosi_r0 <= mosi;  mosi_r1 <= mosi_r0;
        end
    end

    // -------------------------------------------------------------------------
    // Detección de flancos del SCK sincronizado
    // -------------------------------------------------------------------------
    logic sck_rising, sck_falling;
    assign sck_rising  = ( sck_r1 & ~sck_r2);  // flanco de subida detectado
    assign sck_falling = (~sck_r1 &  sck_r2);  // flanco de bajada detectado

    // Selección de flanco de muestreo y desplazamiento según modo SPI
    // Modo 0 (CPOL=0,CPHA=0): muestra en subida, desplaza en bajada
    // Modo 1 (CPOL=0,CPHA=1): muestra en bajada, desplaza en subida
    // Modo 2 (CPOL=1,CPHA=0): muestra en bajada, desplaza en subida
    // Modo 3 (CPOL=1,CPHA=1): muestra en subida, desplaza en bajada
    logic sample_edge, shift_edge;
    generate
        assign sample_edge = (CPOL == 0 && CPHA == 0) ? sck_rising  :
                             (CPOL == 0 && CPHA == 1) ? sck_falling :
                             (CPOL == 1 && CPHA == 0) ? sck_falling :
                                                        sck_rising;

        assign shift_edge  = (CPOL == 0 && CPHA == 0) ? sck_falling :
                             (CPOL == 0 && CPHA == 1) ? sck_rising  :
                             (CPOL == 1 && CPHA == 0) ? sck_rising  :
                                                        sck_falling;
    endgenerate

    // -------------------------------------------------------------------------
    // Registro de desplazamiento y contador de bits
    // -------------------------------------------------------------------------
    logic [7:0] shift_rx;   // Registro de recepción (MSB primero)
    logic [7:0] shift_tx;   // Registro de transmisión
    logic [2:0] bit_cnt;    // Contador de bits 0..7
    logic       active;     // cs_n activo (bajo)

    assign active = ~cs_n_r1;
    assign miso   = shift_tx[7];   // MSB siempre en la salida serie

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_rx  <= 8'h00;
            shift_tx  <= 8'h00;
            bit_cnt   <= 3'd0;
            rx_data   <= 8'h00;
            rx_valid  <= 1'b0;
        end else begin
            rx_valid <= 1'b0;   // pulso de 1 ciclo por defecto

            // Carga del dato de transmisión al activar CS
            if (!cs_n_r1 && cs_n_r1 != cs_n_r0) begin
                shift_tx <= tx_data;
                bit_cnt  <= 3'd0;
            end

            if (active) begin
                // --- Flanco de muestreo: captura MOSI ---
                if (sample_edge) begin
                    shift_rx <= {shift_rx[6:0], mosi_r1};   // desplaza hacia MSB
                    bit_cnt  <= bit_cnt + 1'b1;

                    // Al completar 8 bits, publicar dato recibido
                    if (bit_cnt == 3'd7) begin
                        rx_data  <= {shift_rx[6:0], mosi_r1};
                        rx_valid <= 1'b1;
                        bit_cnt  <= 3'd0;
                    end
                end

                // --- Flanco de desplazamiento: avanza MISO ---
                if (shift_edge) begin
                    shift_tx <= {shift_tx[6:0], 1'b0};
                end
            end
        end
    end

endmodule