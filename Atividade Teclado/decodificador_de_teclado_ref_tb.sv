`timescale 1ns/1ps

module tb_decodificador_de_teclado_ref;

    // =====================================
    // SINAIS
    // =====================================

    logic enable;

    logic [3:0] lin_matriz;
    logic [3:0] col_matriz;

    logic digitos_valid;
    senhaPac_t digitos_value;

    // =====================================
    // INSTÂNCIA DO DUT
    // =====================================

    decodificador_de_teclado_ref dut (
        .enable(enable),
        .lin_matriz(lin_matriz),
        .col_matriz(col_matriz),
        .digitos_valid(digitos_valid),
        .digitos_value(digitos_value)
    );

    // =====================================
    // TASK DE TESTE
    // =====================================

    task automatic press_key(
        input logic [3:0] lin,
        input logic [3:0] col,
        input string nome_tecla
    );
    begin

        lin_matriz = lin;
        col_matriz = col;

        #10;

        $display("======================================");
        $display("TECLA  : %s", nome_tecla);
        $display("LINHA  : %b", lin_matriz);
        $display("COLUNA : %b", col_matriz);
        $display("VALID  : %b", digitos_valid);

        if (digitos_valid)
            $display("VALOR  : %h", digitos_value.digits[0]);

        #10;

    end
    endtask

    // =====================================
    // ESTÍMULOS
    // =====================================

    initial begin

        enable = 0;

        lin_matriz = 4'b1111;
        col_matriz = 4'b1111;

        #20;

        enable = 1;

        // =================================
        // LINHA 0
        // =================================

        press_key(4'b0111, 4'b0111, "1");
        press_key(4'b0111, 4'b1011, "2");
        press_key(4'b0111, 4'b1101, "3");
        press_key(4'b0111, 4'b1110, "A");

        // =================================
        // LINHA 1
        // =================================

        press_key(4'b1011, 4'b0111, "4");
        press_key(4'b1011, 4'b1011, "5");
        press_key(4'b1011, 4'b1101, "6");
        press_key(4'b1011, 4'b1110, "B");

        // =================================
        // LINHA 2
        // =================================

        press_key(4'b1101, 4'b0111, "7");
        press_key(4'b1101, 4'b1011, "8");
        press_key(4'b1101, 4'b1101, "9");
        press_key(4'b1101, 4'b1110, "C");

        // =================================
        // LINHA 3
        // =================================

        press_key(4'b1110, 4'b0111, "*");
        press_key(4'b1110, 4'b1011, "0");
        press_key(4'b1110, 4'b1101, "#");
        press_key(4'b1110, 4'b1110, "D");

        // =================================
        // TESTE INVÁLIDO
        // =================================

        press_key(4'b1111, 4'b1111, "INVALIDO");

        #20;

        $finish;

    end

    // =====================================
    // WAVEFORM
    // =====================================

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_decodificador_de_teclado_ref);
    end

endmodule