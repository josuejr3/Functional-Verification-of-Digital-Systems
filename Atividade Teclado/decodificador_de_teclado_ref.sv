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


module decodificador_de_teclado_ref (

    input logic             enable,
    input logic [3:0]       col_matriz,
    input logic [3:0]      lin_matriz,
    output logic            digitos_valid,
    output senhaPac_t       digitos_value

);

    //      TABELA DE TECLAS - TECLADD 4X4
    // COLUNA 0   COLUNA 1   COLUNA 2   COLUNA 3
    //   1          2          3          A
    //   4          5          6          B
    //   7          8          9          C
    //   *          0          #          D

    // Cria uma constante com o mapeamento do teclado
    localparam logic [3:0] map_keyword[4][4] = '{
        '{4'h1, 4'h2, 4'h3, 4'hA},
        '{4'h4, 4'h5, 4'h6, 4'hB},
        '{4'h7, 4'h8, 4'h9, 4'hC},
        '{4'hE, 4'h0, 4'hF, 4'hD}
    };

    // Always comb responsável por fazer as atribuições
    always_comb begin
        if (!enable) begin
            digitos_valid = 4'b0;
        end else begin
            int line, column;

            case(lin_matriz)                                                        // Mapeamento da linha
                4'b0111:
                    line = 0;
                4'b1011:
                    line = 1;
                4'b1101:
                    line = 2;
                4'b1110:
                    line = 3;
                default:
                    line = -1;                                                      // Valor inválido
            endcase

            case(col_matriz)                                                        // Mapeamento da coluna
                4'b0111:
                    column = 0;
                4'b1011:
                    column = 1;
                4'b1101:
                    column = 2;
                4'b1110:
                    column = 3;
                default:
                    column = -1;                                                    // Valor inválido
            endcase

            if (line != -1 && column != -1) begin
                digitos_valid = 1'b1;                                               // Joga digitos_valid para 1 quando uma tecla valida é pressionada
                digitos_value = senhaPac_t'({16'hFFFF, map_keyword[line][column]}); // Concatena FFFFFFFFFFFFFFFF[line][column]
            end else begin
                digitos_valid = 1'b0;                                               // Joga digitos_valid para 0 quando nenhuma tecla valida é pressionada
                digitos_value = '0;                                                 // Valor padrão quando inválido
            end
        end
    end

endmodule: decodificador_de_teclado_ref