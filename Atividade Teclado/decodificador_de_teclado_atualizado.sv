// =======================================
//               TIPOS
// =======================================

typedef struct packed {
    logic [19:0] [3:0] digits;
} senhaPac_t;

typedef struct packed {
	logic [3:0] BCD0;
    logic [3:0] BCD1;
    logic [3:0] BCD2;
    logic [3:0] BCD3;
    logic [3:0] BCD4;
    logic [3:0] BCD5;
} bcdPac_t;

typedef struct packed {
	logic bip_status;
	logic [5:0] bip_time;
	logic [5:0] tranca_aut_time;
    senhaPac_t  senha_master;
 	senhaPac_t  senha_1;
    senhaPac_t  senha_2;
    senhaPac_t  senha_3;
    senhaPac_t  senha_4;
} setupPac_t;

typedef struct packed {
	logic [19:0] [3:0] digits;
} digitosPac_t;

// =======================================
//           MÓDULO - TECLADO
// =======================================

module decodificador_de_teclado (
    input  logic       clk,
    input  logic       rst,
    input  logic       enable,
    input  logic [3:0] col_matriz,
    output logic [3:0] lin_matriz,
    output digitosPac_t digitos_value, // Tipo corrigido para corresponder ao arquivo
    output logic       digitos_valid
);

    // Parametrização baseada na frequência do Clock (1 kHz)
    localparam CLK_FREQ = 1_000;								// CLK do Sistema
    localparam DEBOUNCE_COUNTER = CLK_FREQ / 10; // 100 ms      // Debounce tecla
    localparam TWO_SEC_COUNTER = 2 * CLK_FREQ;   // 2 s         // Contador de 2 segundos
    localparam ONE_SEC_COUNTER = 1 * CLK_FREQ;   // 1 s         // Contador de 1 segundo
    localparam FIVE_SEC_COUNTER = 5 * CLK_FREQ;  // 5 s         // Contador de 5 segundos

    enum logic [3:0] {
        INIT, 
        SCAN, 
        DEBOUNCE, 
        VALID_KEY, 
        OUTPUT_READY, 
        DECODE,
        TIMEOUT,
        TIMEOUT_VALID,
        HOLD,
        LIMPA
    } estado;

    // Contadores dinâmicos baseados no Clock
    logic [$clog2(DEBOUNCE_COUNTER)-1:0] Tcont_db;
    logic [$clog2(FIVE_SEC_COUNTER)-1:0] Tcont_timeout;
    logic [$clog2(TWO_SEC_COUNTER)-1:0]  Tcont_hold; // Novo contador para o auto-repeat

    logic [3:0] reg_linha;
    logic [3:0] reg_coluna;
    logic [3:0] value;
    
    logic flag_B2s; // Flag para controlar repetição da tecla no estado HOLD

    digitosPac_t reg_digitos_value; // Usando o struct correto

    logic BP;
    logic BS;

    assign lin_matriz = reg_linha;

    always_ff @(posedge clk or posedge rst or negedge enable) begin
        if(rst || !enable) begin
            estado <= INIT;
            reg_linha <= 4'b0111;
            reg_coluna <= 4'b1111;
            value <= 4'hF;
            Tcont_db <= 0;
            Tcont_timeout <= 0;
            Tcont_hold <= 0;
            flag_B2s <= 0;
            reg_digitos_value.digits <= {20{4'hF}};

        end else begin
            case (estado)
                INIT: begin
                    estado <= SCAN;
                end

                SCAN: begin
                    if(Tcont_timeout >= FIVE_SEC_COUNTER - 1) estado <= TIMEOUT;
                    else begin
                        if(digitos_value.digits != {20{4'hF}}) Tcont_timeout <= Tcont_timeout + 1;
                        if(BP) begin
                            estado <= DEBOUNCE;
                            reg_coluna <= col_matriz;
                            Tcont_db <= 0;
                        end else begin
                            reg_linha <= {reg_linha[0], reg_linha[3:1]};
                            reg_coluna <= 4'b1111;
                        end
                    end
                end

                DEBOUNCE: begin
                    if(Tcont_timeout >= FIVE_SEC_COUNTER - 1) estado <= TIMEOUT;
                    else begin 
                        if(digitos_value.digits != {20{4'hF}}) Tcont_timeout <= Tcont_timeout + 1;
                        if(BS) begin
                            estado <= SCAN;
                            Tcont_db <= 0;
                        end else if (Tcont_db >= DEBOUNCE_COUNTER - 1)begin
                            estado <= DECODE;
                        end else if (BP) begin
                            estado <= DEBOUNCE;
                            Tcont_db <= Tcont_db + 1;
                        end else estado <= DEBOUNCE;
                    end
                end

                TIMEOUT: begin
                    reg_digitos_value.digits <= {20{4'hE}};
                    estado <= TIMEOUT_VALID;
                    Tcont_timeout <= 0;
                end

                TIMEOUT_VALID: begin
                    reg_digitos_value.digits <= {20{4'hF}};
                    estado <= SCAN;
                end

                DECODE: begin
                    value <= decoder(reg_linha, reg_coluna);
                    estado <= OUTPUT_READY;
                    Tcont_timeout <= 0;
                    Tcont_db <= 0;
                end

                OUTPUT_READY: begin
                  if((value != 4'hA) && (value != 4'hB) && (value != 4'hF)) begin
                        reg_digitos_value.digits <= {reg_digitos_value.digits[18:0], value};
                        estado <= HOLD;
                        Tcont_hold <= 0; // Prepara contador para possível repetição
                        flag_B2s <= 0;   // Zera flag da repetição
                    end else if(value == 4'hA) begin 
                        estado <= VALID_KEY; 
                    end else if(value == 4'hB) begin 
                        estado <= VALID_KEY;
                        reg_digitos_value.digits <= {20{4'hB}};
                    end else begin
                        estado <= SCAN; // Prevenção contra falsas leituras
                    end
                end

                VALID_KEY: begin
                    estado <= LIMPA;
                end

                HOLD: begin
                    if(BS) begin
                        estado <= SCAN;
                        flag_B2s <= 0;
                    end else begin
                        // Lógica de Repetição (Auto-repeat): Aguarda 2s e depois 1s
                        if((Tcont_hold >= ONE_SEC_COUNTER && flag_B2s) || (Tcont_hold >= TWO_SEC_COUNTER)) begin
                            reg_digitos_value.digits <= {reg_digitos_value.digits[18:0], value};
                            Tcont_hold <= 0;
                            flag_B2s <= 1; // Ativa flag indicando que já passou de 2s
                        end else begin
                            Tcont_hold <= Tcont_hold + 1;
                        end
                    end
                end

                LIMPA: begin
                    reg_digitos_value.digits <= {20{4'hF}};
                    // Se estiver limpando, melhor voltar ao SCAN para evitar repetição acidental de '*' ou '#'
                    if (BS) estado <= SCAN; 
                end

            endcase
        end
    end


    always_comb begin
        case (estado)
            INIT: begin
                digitos_valid = 0;
                digitos_value = {20{4'hF}};
            end
            SCAN: begin
                digitos_valid = 0;
                digitos_value = reg_digitos_value;
            end
            DEBOUNCE: begin
                digitos_valid = 0;
                digitos_value = reg_digitos_value;
            end
            DECODE: begin
                digitos_valid = 0;
                digitos_value = reg_digitos_value;
            end
            OUTPUT_READY: begin
                digitos_valid = 0;
                digitos_value = reg_digitos_value;
            end
            VALID_KEY: begin
                digitos_valid = 1;
                digitos_value = reg_digitos_value;
            end
            TIMEOUT: begin
                digitos_valid = 0;
                digitos_value = reg_digitos_value;
            end
            TIMEOUT_VALID: begin
                digitos_valid = 1;
                digitos_value = reg_digitos_value;
            end
            HOLD: begin
                digitos_valid = 0;
                digitos_value = reg_digitos_value;
            end
            LIMPA: begin
                digitos_valid = 0;
                digitos_value = {20{4'hF}};
            end
            default: begin
                digitos_valid = 0;
                digitos_value = {20{4'hF}};
            end
        endcase
    end

    always_comb begin
        if( col_matriz == 4'b0111 ||
            col_matriz == 4'b1011 ||
            col_matriz == 4'b1101 ||
            col_matriz == 4'b1110) BP = 1;
        else BP = 0;

        if(col_matriz == 4'b1111) BS = 1;
        else BS = 0;
    end

    function logic [3:0] decoder(input logic [3:0] linha, input logic [3:0] coluna);
        case ((linha << 4 | coluna))
            8'b01110111: decoder = 4'h1;
            8'b01111011: decoder = 4'h2;
            8'b01111101: decoder = 4'h3;
            8'b10110111: decoder = 4'h4;
            8'b10111011: decoder = 4'h5;
            8'b10111101: decoder = 4'h6;
            8'b11010111: decoder = 4'h7;
            8'b11011011: decoder = 4'h8;
            8'b11011101: decoder = 4'h9;
            8'b11101011: decoder = 4'h0;
            8'b11100111: decoder = 4'hA; // Dígito *
            8'b11101101: decoder = 4'hB; // Dígito #
            default: decoder = 4'hF;
        endcase
    endfunction
endmodule