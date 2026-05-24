module decodificador_de_teclado_tb;
  
  // ==============================================
  //    Parâmetros de entrada e saída do módulo
  // ==============================================
  logic [3:0] lin_matriz;
  logic [3:0] col_matriz;
  logic enable;
  logic digitos_valid_DUV;
  digitosPac_t digitos_value_DUV;
  bit clk;
  logic rst;
  
  // Variáveis de controle para o Teclado Virtual (Combinacional)
  logic [3:0] tecla_linha_alvo;
  logic [3:0] tecla_coluna_alvo;
  logic       tecla_pressionada;
  logic       injetar_ruido;
  logic       ruido_estado;

  // ==============================================
  //              INSTANCIAÇÃO DO DUV
  // ==============================================
  decodificador_de_teclado decode_DUV (
    .clk            (clk),
    .rst            (rst),
    .enable         (enable),
    .lin_matriz     (lin_matriz),
    .col_matriz     (col_matriz),
    .digitos_valid  (digitos_valid_DUV),
    .digitos_value  (digitos_value_DUV)
  );

  // ==============================================
  //    MODELO DE REFERÊNCIA INTERNO
  // ==============================================
  // Espelha exatamente o decode_keypad() do DUV.
  // Parâmetros derivados do design.sv para manter sincronia:
  //   CLK_FREQ        = 1_000
  //   DEBOUNCE_COUNTER = CLK_FREQ / 10 = 100 ciclos
  //
  // Fluxo do DUV até o shift ocorrer:
  //   SCAN (≤4 ciclos) → DEBOUNCE (100 ciclos) → DECODE (1) → SHIFT_TECLA (1)
  //   Total mínimo: 106 ciclos | Margem segura adotada: 130 ciclos
  //
  // A verificação é feita APÓS os 130 ciclos, quando digits[0] já contém
  // a tecla recém-inserida pelo SHIFT_TECLA.

  localparam int CICLOS_ATE_SHIFT = 130; // DEBOUNCE(100) + SCAN(≤4) + DECODE(1) + SHIFT(1) + folga

  function automatic logic [3:0] ref_decodificar(
    input logic [3:0] lin,
    input logic [3:0] col
  );
    // Tabela idêntica ao decode_keypad() do DUV (design.sv)
    case ({lin, col})
      8'b0111_0111: return 4'h1;
      8'b0111_1011: return 4'h2;
      8'b0111_1101: return 4'h3;
      8'b0111_1110: return 4'hE;
      8'b1011_0111: return 4'h4;
      8'b1011_1011: return 4'h5;
      8'b1011_1101: return 4'h6;
      8'b1011_1110: return 4'hE;
      8'b1101_0111: return 4'h7;
      8'b1101_1011: return 4'h8;
      8'b1101_1101: return 4'h9;
      8'b1101_1110: return 4'hE;
      8'b1110_0111: return 4'hA; // *
      8'b1110_1011: return 4'h0; // 0
      8'b1110_1101: return 4'hB; // #
      8'b1110_1110: return 4'hE;
      default:      return 4'hE;
    endcase
  endfunction

  // ==============================================
  //    LÓGICA COMBINACIONAL DO TECLADO MATRICIAL
  // ==============================================
  always_comb begin
    if (tecla_pressionada && (lin_matriz == tecla_linha_alvo)) begin
      if (injetar_ruido && ruido_estado)
        col_matriz = 4'b1111; // Simula bouncing
      else
        col_matriz = tecla_coluna_alvo;
    end else begin
      col_matriz = 4'b1111;
    end
  end

  // Gerador de ruído aleatório assíncrono independente
  always #2 if (injetar_ruido) ruido_estado = $urandom_range(0,1);

  // ==============================================
  //             GRUPOS DE MONITORAMENTO
  // ==============================================

  // 2 bins reais: enable ligado e desligado
  covergroup CG_ENABLE @(posedge clk);
    coverpoint enable {
      bins ativo   = {1};
      bins inativo = {0};
    }
  endgroup

  // 4 bins reais: apenas as linhas que o DUV efetivamente drive
  covergroup CG_LIN @(lin_matriz);
    coverpoint lin_matriz {
      bins row0 = {4'b1110};
      bins row1 = {4'b1101};
      bins row2 = {4'b1011};
      bins row3 = {4'b0111};
    }
  endgroup

  // 4 bins reais de coluna: 3 colunas pressionadas + repouso
  covergroup CG_COL @(col_matriz);
    coverpoint col_matriz {
      bins col0    = {4'b0111};
      bins col1    = {4'b1011};
      bins col2    = {4'b1101};
      bins repouso = {4'b1111};
    }
  endgroup

  // 2 bins reais: valid pulsado ou nao
  covergroup CG_Digitos_Valid @(posedge clk);
    coverpoint digitos_valid_DUV {
      bins pulsado = {1};
      bins ocioso  = {0};
    }
  endgroup

  // 11 bins reais: digitos 0-9 mais confirmacao '*' (0xA)
  // '#' (0xB) limpa o barramento, nao gera shift de digito
  // 0xF e o valor de reset (invalido), 0xE e erro interno
  covergroup CG_Digitos_Value @(posedge clk);
    coverpoint digitos_value_DUV.digits[0]
      iff (digitos_valid_DUV) {

      bins digito[10]  = {[4'h0 : 4'h9]};
      
      bins confirmacao = {4'hA};
      ignore_bins reset_val = {4'hF};
      ignore_bins erro_val  = {4'hE};
      ignore_bins hashtag   = {4'hB};
    }
  endgroup
  
  CG_ENABLE        cg_enable_inst        = new;
  CG_LIN           cg_lin_inst           = new;
  CG_COL           cg_col_inst           = new;
  CG_Digitos_Valid cg_digitos_valid_inst = new;
  CG_Digitos_Value cg_digitos_value_inst = new;

  // Gerador de Clock de 10ns
  always #5 clk = ~clk;

  // Task de Reset Global síncrono
  task automatic reset();
    @(posedge clk); rst = 1;
    repeat(5) @(posedge clk);
    rst = 0;
  endtask
  
  // ====================================================================
  // TASK DE ESTIMULOS: Injeta tecla e autovalida o resultado no DUV
  // ====================================================================
  task automatic pressionar_tecla(
    input [3:0] linha,
    input [3:0] coluna,
    input int   ciclos_duracao,
    input bit   com_ruido
  );
    logic [3:0] valor_ref;

    tecla_linha_alvo  = linha;
    tecla_coluna_alvo = coluna;

    // ------------------------------------------------------------------
    // Fase de ruído mecânico (bouncing): 120 ciclos com col instável.
    // O debounce do DUV só começa a contar após a coluna estabilizar,
    // portanto estes ciclos NÃO contam para CICLOS_ATE_SHIFT.
    // ------------------------------------------------------------------
    if (com_ruido) begin
      injetar_ruido     = 1;
      tecla_pressionada = 1;
      repeat(120) @(posedge clk);
      injetar_ruido     = 0; // Coluna estabiliza a partir daqui
    end else begin
      tecla_pressionada = 1;
    end

    // ------------------------------------------------------------------
    // Aguarda o fluxo completo do DUV:
    //   SCAN (≤4) → DEBOUNCE (100) → DECODE (1) → SHIFT_TECLA (1) + folga
    // ------------------------------------------------------------------
    repeat(CICLOS_ATE_SHIFT) @(posedge clk);

    // ------------------------------------------------------------------
    // VERIFICAÇÃO: digits[0] deve conter a tecla recém-shiftada
    // ------------------------------------------------------------------
    if (enable && !rst) begin
      valor_ref = ref_decodificar(linha, coluna); // Usa linha/coluna alvo, não os sinais
                                                   // que podem estar em 4'b1111 neste momento
      
      // Filtra teclas que não geram shift (E = erro interno do DUV)
      if (valor_ref !== 4'hE) begin
        if (digitos_value_DUV.digits[0] !== valor_ref) begin
          $display("\n[ERRO] DUV retornou valor incorreto em digits[0]!");
          $display("  Tempo: %0t ns | Tecla esperada (REF): %h | DUV digits[0]: %h",
                   $time, valor_ref, digitos_value_DUV.digits[0]);
          $display("  lin_alvo=%b  col_alvo=%b", linha, coluna);
          $finish;
        end else begin
          $display("[OK] Tecla %h armazenada corretamente em digits[0].", valor_ref);
          $display("     %0t | EN:%b ROW:%b COL:%b | Valid:%b | digits:%h",
                   $time, enable, lin_matriz, col_matriz,
                   digitos_valid_DUV, digitos_value_DUV.digits);
        end
      end
    end

    // Completa a duração restante da tecla pressionada
    if (ciclos_duracao > CICLOS_ATE_SHIFT)
      repeat(ciclos_duracao - CICLOS_ATE_SHIFT) @(posedge clk);

    // Solta a tecla e aguarda estabilização para a próxima varredura
    tecla_pressionada = 0;
    repeat(40) @(posedge clk);
  endtask

  // ====================================================================
  //    MAPEAMENTO DO TECLADO MATRICIAL (alinhado com o DUV)
  // ====================================================================
  //                          0        1        2        3        4        5        6        7        8        9       10(*)    11(#)
  logic [3:0] pad_linhas  [12] = '{4'b1110, 4'b0111, 4'b0111, 4'b0111, 4'b1011, 4'b1011, 4'b1011, 4'b1101, 4'b1101, 4'b1101, 4'b1110, 4'b1110};
  logic [3:0] pad_colunas [12] = '{4'b1011, 4'b0111, 4'b1011, 4'b1101, 4'b0111, 4'b1011, 4'b1101, 4'b0111, 4'b1011, 4'b1101, 4'b0111, 4'b1101};

  // ==============================================
  //              BLOCO PRINCIPAL DE TESTES
  // ==============================================
  initial begin
    int tecla_sorteada;
    int duracao_sorteada;
    bit ruido_sorteado;

    enable            = 1;
    tecla_pressionada = 0;
    injetar_ruido     = 0;
    ruido_estado      = 0;
    tecla_linha_alvo  = 4'b1111;
    tecla_coluna_alvo = 4'b1111;
    
    reset();
    
    $display("------ INICIANDO TESTES ALEATÓRIOS (RANDOM) ------");

    // --- 1. TESTE ALEATÓRIO DE DECODIFICAÇÃO E SHIFT ---
    $display("Iniciando digitação de 25 teclas numéricas aleatórias...");
    repeat (100) begin
      tecla_sorteada   = $urandom_range(0, 9);
      // Duração mínima = CICLOS_ATE_SHIFT + folga de 40 do WAIT_RELEASE
      duracao_sorteada = $urandom_range(CICLOS_ATE_SHIFT + 50, 400);
      ruido_sorteado   = $urandom_range(0, 1);
      enable = $urandom_range(0, 1);
      
      $display("[RANDOM] Tecla: %0d | Duração: %0d ciclos | Ruído: %0b",
               tecla_sorteada, duracao_sorteada, ruido_sorteado);
               
      pressionar_tecla(pad_linhas[tecla_sorteada], pad_colunas[tecla_sorteada],
                       duracao_sorteada, ruido_sorteado);
    end

    // ------------------------------------------------------------------
    // RELATÓRIO DE COBERTURA — CENÁRIO 1
    // get_coverage() retorna valor real [0.0–100.0] de cada covergroup
    // ------------------------------------------------------------------
    $display("");
    $display("========================================================");
    $display("  COBERTURA FUNCIONAL — CENÁRIO 1 (25 teclas aleatórias)");
    $display("========================================================");
    $display("  CG_ENABLE        : %0.2f%%", cg_enable_inst.get_coverage());
    $display("  CG_LIN           : %0.2f%%", cg_lin_inst.get_coverage());
    $display("  CG_COL           : %0.2f%%", cg_col_inst.get_coverage());
    $display("  CG_Digitos_Valid : %0.2f%%", cg_digitos_valid_inst.get_coverage());
    $display("  CG_Digitos_Value : %0.2f%%", cg_digitos_value_inst.get_coverage());
    $display("  COBERTURA GLOBAL : %0.2f%%", $get_coverage());
    $display("========================================================");
    $display("");

    // --- 2. TESTE DE REPETIÇÃO AUTOMÁTICA (autorepeat > 2s) ---
    tecla_sorteada = $urandom_range(0, 9);
    $display("Testando autorepetição com a tecla: %0d...", tecla_sorteada);
    pressionar_tecla(pad_linhas[tecla_sorteada], pad_colunas[tecla_sorteada], 4500, 0);

    // --- 3. CONFIRMAÇÃO COM '*' ---
    $display("Enviando tecla de confirmação '*'...");
    pressionar_tecla(pad_linhas[10], pad_colunas[10], 250, 0);
    
    repeat(100) @(posedge clk);

    $display("------ TESTES CONCLUÍDOS COM SUCESSO ------");
    $finish;
  end
  
  // ==============================================
  //        GERADOR DO WAVEFORM (EPWave/VCD)
  // ==============================================
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, decodificador_de_teclado_tb);
  end
  
endmodule: decodificador_de_teclado_tb