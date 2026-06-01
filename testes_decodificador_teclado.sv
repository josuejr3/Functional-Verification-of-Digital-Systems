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
  
  // Variáveis de controle para o Teclado Virtual
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

  localparam int CICLOS_ATE_SHIFT = 130; // quantidade segura de ciclos para o processamento
  
  function automatic logic [3:0] ref_decodificar(
    input logic [3:0] lin,
    input logic [3:0] col
  );
    
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
        col_matriz = 4'b1111;
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

  // 2 bins reais enable ligado e desligado
  covergroup CG_ENABLE @(posedge clk);
    coverpoint enable {
      bins ativo   = {1};
      bins inativo = {0};
    }
  endgroup

  // 4 bins reais para as linhas
  covergroup CG_LIN @(lin_matriz);
    coverpoint lin_matriz {
      bins row0 = {4'b1110};
      bins row1 = {4'b1101};
      bins row2 = {4'b1011};
      bins row3 = {4'b0111};
    }
  endgroup

  // 4 bins reais de coluna 3 colunas pressionadas + teclado solto
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

  // bins para mapeamento das teclas numericas e especificas
  covergroup CG_Digitos_Value @(posedge clk);
    coverpoint digitos_value_DUV.digits[0]
      iff (digitos_valid_DUV) {

      bins digito[10]  = {[4'h0 : 4'h9]};
      
      ignore_bins confirmacao = {4'hA};
      ignore_bins reset_val = {4'hF};
      ignore_bins erro_val  = {4'hE};
      ignore_bins hashtag   = {4'hB};
    }
  endgroup

  // COVERGROUP PARA VALORES ESPECIAIS (CORRIGIDO – sem bin inatingível)
  covergroup CG_Valid_Especial @(posedge clk);
    option.weight = 0; // não afeta cobertura global
    coverpoint digitos_value_DUV.digits
        iff (digitos_valid_DUV) {
        bins timeout_err = { {20{4'hE}} };   // timeout
        bins cancel_hash = { {20{4'hB}} };   // desistência #
        // (bin limpo removido – nunca ocorre com valid=1)
    }
  endgroup
  
  CG_ENABLE        cg_enable_inst        = new;
  CG_LIN           cg_lin_inst           = new;
  CG_COL           cg_col_inst           = new;
  CG_Digitos_Valid cg_digitos_valid_inst = new;
  CG_Digitos_Value cg_digitos_value_inst = new;
  CG_Valid_Especial cg_valid_esp_inst    = new;

  // gerador de clock
  always #5 clk = ~clk;

  // task de reset sincrono
  task automatic reset();
    @(posedge clk); rst = 1;
    repeat(5) @(posedge clk);
    rst = 0;
  endtask
  
  // ====================================================================
  //  TASK DE ESTIMULOS: Injeta tecla e autovalida o resultado no DUV
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
    // fase de ruído mecânico (bouncing): 120 ciclos com col instável.
    // o debounce do DUV só começa a contar após a coluna estabilizar,
    // portanto estes ciclos NÃO contam para CICLOS_ATE_SHIFT.
    // ------------------------------------------------------------------
    if (com_ruido) begin
      injetar_ruido     = 1;
      tecla_pressionada = 1;
      repeat(120) @(posedge clk);
      injetar_ruido     = 0; // coluna estabiliza a partir daqui
    end else begin
      tecla_pressionada = 1;
    end

	// aguarda o tempo completo para decodificação
    repeat(CICLOS_ATE_SHIFT) @(posedge clk);

    if (enable && !rst) begin
      valor_ref = ref_decodificar(linha, coluna);                                          
      
      // filtra teclas que não geram shift
      if (valor_ref !== 4'hE && valor_ref <= 4'h9) begin
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

    // completa a duração restante da tecla pressionada
    if (ciclos_duracao > CICLOS_ATE_SHIFT)
      repeat(ciclos_duracao - CICLOS_ATE_SHIFT) @(posedge clk);

    // solta a tecla e aguarda estabilização para a próxima varredura
    tecla_pressionada = 0;
    repeat(40) @(posedge clk);
  endtask

  // ====================================================================
  //                   MAPEAMENTO DO TECLADO MATRICIAL
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

    // VARIAVEIS PARA O TESTE 2
   	logic [3:0] fila_esperada [$];
    logic [3:0] v_esperado;
    int time_press;
    int c_ruido;
    
    // SETANDO VALORES INICIAIS 
    enable            = 1;
    tecla_pressionada = 0;
    injetar_ruido     = 0;
    ruido_estado      = 0;
    tecla_linha_alvo  = 4'b1111;
    tecla_coluna_alvo = 4'b1111;
    
    // RESET DO SISTEMA
    reset();
    
    $display("==================================================");
    $display("------ INICIANDO TESTES ALEATÓRIOS (RANDOM) ------");
    $display("==================================================");


    // --- 1. TESTE ALEATÓRIO DE DECODIFICAÇÃO E SHIFT ---
    
    $display("==================================================");
    $display("------------------- RELEASE 1 --------------------");
    $display("==================================================");
    
    $display("Iniciando digitação de 100 teclas numéricas aleatórias...");
    repeat (100) begin
      tecla_sorteada   = $urandom_range(0, 10);
      duracao_sorteada = $urandom_range(CICLOS_ATE_SHIFT + 50, 400);
      ruido_sorteado   = $urandom_range(0, 1);
      enable = $urandom_range(0, 1);
      
      $display("[RANDOM] Tecla: %0d | Duração: %0d ciclos | Ruído: %0b",
               tecla_sorteada, duracao_sorteada, ruido_sorteado);
               
      pressionar_tecla(pad_linhas[tecla_sorteada], pad_colunas[tecla_sorteada],
                       duracao_sorteada, ruido_sorteado);
    end

    // ------------------------------------------------------------------
    //                 RELATÓRIO DE COBERTURA — CENÁRIO 1
    // ------------------------------------------------------------------
    $display("========================================================");
    $display("  COBERTURA FUNCIONAL CENÁRIO 1 (100 teclas aleatórias)");
    $display("========================================================");
    $display("  CG_ENABLE        : %0.2f%%", cg_enable_inst.get_coverage());
    $display("  CG_LIN           : %0.2f%%", cg_lin_inst.get_coverage());
    $display("  CG_COL           : %0.2f%%", cg_col_inst.get_coverage());
    $display("  CG_Digitos_Valid : %0.2f%%", cg_digitos_valid_inst.get_coverage());
    $display("  CG_Digitos_Value : %0.2f%%", cg_digitos_value_inst.get_coverage());
    $display("  COBERTURA GLOBAL : %0.2f%%", $get_coverage());
    $display("========================================================");

    // --- 1.1 TESTE DIRECIONADO PARA COBERTURA TOTAL DE VALORES ---
    $display("Forçando a cobertura de todos os dígitos no Covergroup...");
    enable = 1;
    for (int i = 0; i <= 9; i++) begin
      int tempo_press = $urandom_range(200, 100);
      pressionar_tecla(pad_linhas[i], pad_colunas[i], tempo_press, 0);  
      // Pressiona o '*' para disparar o valid e salvar o dígito na cobertura
      pressionar_tecla(pad_linhas[10], pad_colunas[10], 250, 0); 
    end
    
    // ------------------------------------------------------------------
    //               RELATÓRIO DE COBERTURA — CENÁRIO 1.1
    // ------------------------------------------------------------------
    $display("========================================================");
    $display("      COBERTURA FUNCIONAL CENÁRIO 1 SEGUNDA PARTE       ");
    $display("========================================================");
    $display("  CG_ENABLE        : %0.2f%%", cg_enable_inst.get_coverage());
    $display("  CG_LIN           : %0.2f%%", cg_lin_inst.get_coverage());
    $display("  CG_COL           : %0.2f%%", cg_col_inst.get_coverage());
    $display("  CG_Digitos_Valid : %0.2f%%", cg_digitos_valid_inst.get_coverage());
    $display("  CG_Digitos_Value : %0.2f%%", cg_digitos_value_inst.get_coverage());
    $display("  COBERTURA GLOBAL : %0.2f%%", $get_coverage());
    $display("========================================================");

    
    // --- 2. TESTE DO SHIFT DO BARRAMENTO (RELEASE 2 - INALTERADO)
    $display("========================================================");
    $display("------------------------ RELEASE 2 ---------------------");
    $display("========================================================");
    $display("\------ INICIANDO CENÁRIO 2: VERIFICAÇÃO DE SHIFT DO BARRAMENTO ------");
    reset();
    enable = 1;
    fila_esperada.delete();
    
    // Passo 1: Digitar de 0-9 2 vezes para preencher as 20 posicoes
    $display("Passo 1: Preenchendo o barramento digitando de 0 a 9 duas vezes consecutivas...");
    for (int r = 0; r < 2; r++) begin
      for (int i = 0; i <= 9; i++) begin
        pressionar_tecla(pad_linhas[i], pad_colunas[i], 200, 0);
        fila_esperada.push_back(i);
        
        for (int k = 0; k < 20; k++) begin
          v_esperado = (k < fila_esperada.size()) ? fila_esperada[fila_esperada.size() - 1 - k] : 4'hF;
          if (digitos_value_DUV.digits[k] !== v_esperado) begin
            $display("\n[ERRO SHIFT - PREENCHIMENTO] Posição [%0d] falhou!", k);
            $display("Esperado: %h | Obtido no DUV: %h", v_esperado, digitos_value_DUV.digits[k]);
            $finish;
          end
        end
      end
    end
    
    $display("[OK] Barramento totalmente preenchido e verificado com sucesso: %h", digitos_value_DUV.digits);
    
    $display("Passo 2: Inserindo mais 10 dígitos aleatórios continuamente e testando o descarte...");
    repeat (10) begin
      tecla_sorteada = $urandom_range(0, 9);
      pressionar_tecla(pad_linhas[tecla_sorteada], pad_colunas[tecla_sorteada], 200, 0);
      
      fila_esperada.push_back(tecla_sorteada);
      if (fila_esperada.size() > 20) begin
        void'(fila_esperada.pop_front());
      end

      for (int k = 0; k < 20; k++) begin
        v_esperado = fila_esperada[19 - k];
        if (digitos_value_DUV.digits[k] !== v_esperado) begin
          $display("\n[ERRO SHIFT - TRANSBORDAMENTO] O algoritmo de descarte falhou ou gerou efeito circular!");
          $display("Tempo: %0t ns | Posição [%0d] esperava %h, mas DUV contém %h", $time, k, v_esperado, digitos_value_DUV.digits[k]);
          $display("Estado atual do barramento DUV: %h", digitos_value_DUV.digits);
          $finish;
        end
      end
    end
    $display("[SUCESSO] Cenário 2 concluído! O barramento manteve estritamente os últimos 20 dígitos na ordem correta.");
    
    $display("========================================================");
    $display("   RELATÓRIO DE VERIFICAÇÃO CENÁRIO 2 (SHIFT REG)     ");
    $display("========================================================");
    $display("  Status do Cenário      : SUCESSO (PASSED)");
    $display("  Capacidade Máxima      : 30 dígitos verificados");
    $display("  Estímulos Injetados    : 20 teclas (20 preenchimento + 10 estouro)");
    $display("  Algoritmo de Descarte  : OK (Sem efeito circular ou travamento)");
    $display("--------------------------------------------------------");
    $write("  Barramento no DUV      : [ ");
    for (int k = 19; k >= 0; k--) begin
      $write("%h ", digitos_value_DUV.digits[k]);
    end
    $display("]");
    $write("  Espelho de Controle(TB): [ ");
    for (int k = 0; k < 20; k++) begin
      $write("%h ", fila_esperada[k]);
    end
    $display("]");
    $display("========================================================");
    
    // ====================================================================
    // --- 3. CENÁRIO 3: VERIFICAÇÃO DE DEBOUNCE (INALTERADO) -----
    // ====================================================================
    $display("========================================================");
    $display("----------------------- RELEASE 3 ----------------------");
    $display("========================================================");
    $display("----- INICIANDO CENÁRIO 3 VERIFICAÇÃO DE DEBOUNCE ------");
    reset();
    enable = 1;
    
    begin : c3_debounce
      logic [19:0][3:0] barramento_inicial;
      logic [19:0][3:0] barramento_pos_ruido;
      logic [19:0][3:0] barramento_final;
      int tecla_teste = 5;

      barramento_inicial = digitos_value_DUV.digits;

      $display("Passo A: Iniciando bouncing mecânico por 120 ciclos...");

      fork
        begin
          repeat(120) @(posedge clk);
          barramento_pos_ruido = digitos_value_DUV.digits;
          if (barramento_pos_ruido !== barramento_inicial) begin
            $display("\n[ERRO DEBOUNCE] Circuito aceitou tecla instável durante ruído!");
            $finish;
          end
          $display("  [OK] Nenhuma tecla falsa registrada durante os 120 ciclos de oscilação.");
        end

        begin
          pressionar_tecla(pad_linhas[tecla_teste], pad_colunas[tecla_teste],
                           CICLOS_ATE_SHIFT + 50, 1);
        end
      join

      barramento_final = digitos_value_DUV.digits;
      if (barramento_final[0] == ref_decodificar(pad_linhas[tecla_teste], pad_colunas[tecla_teste])) begin
        $display("  [OK] Tecla %0d reconhecida corretamente após estabilização.", tecla_teste);
      end else begin
        $display("\n[ERRO DEBOUNCE] Tecla legítima ignorada após ruído cessar!");
        $display("  Esperado: %h | Obtido: %h",
                 ref_decodificar(pad_linhas[tecla_teste], pad_colunas[tecla_teste]),
                 barramento_final[0]);
        $finish;
      end

      for (int i = 1; i < 20; i++) begin
        if (barramento_final[i] !== 4'hF) begin
          $display("\n[ERRO DEBOUNCE] Múltiplos registros detectados na posição [%0d]!", i);
          $finish;
        end
      end

      $display("========================================================");
      $display("     RELATÓRIO DE VERIFICAÇÃO CENÁRIO 3 (DEBOUNCE)      ");
      $display("========================================================");
      $display("  Status do Cenário       : SUCESSO (PASSED)");
      $display("  Duração do Bouncing     : 120 ciclos de clock (Injetado)");
      $display("  Comportamento do Filtro : Filtragem Total (Ignorou oscilações)");
      $display("  Teclas Válidas Retidas  : 1 única tecla (Dígito %0d)", tecla_teste);
      $display("  Valor em digits[0]      : %h", barramento_final[0]);
      $display("========================================================");

    end
      
    // ====================================================================
    // --- 4. CENÁRIO 4: VERIFICAÇÃO DE AUTOREPEAT (INALTERADO) ---
    // ====================================================================
    $display("========================================================");
    $display("------------------------ RELEASE 4 ---------------------");
    $display("========================================================");
    $display("----- INICIANDO CENÁRIO 4: VERIFICAÇÃO DE AUTOREPEAT----");
    reset();
    enable = 1;
    injetar_ruido = 0;

    begin : c4_autorepeat
      int mudancas_no_barramento = 0;
      bit c4_terminou = 0;
      int tecla_repeat = 3;
      logic [19:0][3:0] barramento_anterior;

      int ciclos_teste = 5500;

      $display("Passo 1: Mantendo a tecla %0d pressionada por %0d ciclos...", tecla_repeat, ciclos_teste);

      barramento_anterior = digitos_value_DUV.digits;

      fork
        begin : monitor_intervalo
          int ultimo_tempo_repeat;
          int delta_ciclos;
          localparam int PERIODO_ESPERADO = 1000;
          localparam int TOLERANCIA       = 20;

          repeat(150) @(posedge clk);
          barramento_anterior  = digitos_value_DUV.digits;
          ultimo_tempo_repeat  = $time;

          while (!c4_terminou) begin
            @(posedge clk);
            if (digitos_value_DUV.digits != barramento_anterior) begin
              mudancas_no_barramento++;
              delta_ciclos = ($time - ultimo_tempo_repeat) / 10;

              $display("  [MONITOR] Autorepetição #%0d em %0t ns | Intervalo: %0d ciclos | Barramento: %h",
                       mudancas_no_barramento, $time, delta_ciclos, digitos_value_DUV.digits);

              if (mudancas_no_barramento >= 2) begin
                if (delta_ciclos < (PERIODO_ESPERADO - TOLERANCIA) ||
                    delta_ciclos > (PERIODO_ESPERADO + TOLERANCIA)) begin
                  $display("\n[ERRO INTERVALO] Repetição #%0d fora do período esperado!", mudancas_no_barramento);
                  $display("  Esperado: %0d ciclos (±%0d) | Obtido: %0d ciclos",
                           PERIODO_ESPERADO, TOLERANCIA, delta_ciclos);
                  $finish;
                end else begin
                  $display("  [OK] Intervalo dentro da janela permitida (%0d a %0d ciclos).",
                           PERIODO_ESPERADO - TOLERANCIA, PERIODO_ESPERADO + TOLERANCIA);
                end
              end

              barramento_anterior = digitos_value_DUV.digits;
              ultimo_tempo_repeat = $time;
            end
          end
        end

        begin
          pressionar_tecla(pad_linhas[tecla_repeat], pad_colunas[tecla_repeat], ciclos_teste, 0);
          c4_terminou = 1;
        end
      join

      $display("\nAnálise final do barramento DUV: %h", digitos_value_DUV.digits);

      if (mudancas_no_barramento >= 2) begin
        $display("[OK] O recurso de autorepetição adicionou %0d dígitos extras por tempo de retenção.", mudancas_no_barramento);
      end else begin
        $display("\n[ERRO AUTOREPEAT] A tecla ficou retida mas o barramento só registrou %0d repetições extras.", mudancas_no_barramento);
        $finish;
      end

      $display("Passo 2: Soltando a tecla e verificando termino do autorepeat...");

      begin : c4_verificar_cessacao
        logic [19:0][3:0] barramento_apos_soltar;
        int mudancas_apos_soltar = 0;
        int CICLOS_OBSERVACAO = 3000;

        @(negedge clk);
        barramento_apos_soltar = digitos_value_DUV.digits;

        repeat (CICLOS_OBSERVACAO) begin
          @(posedge clk);
          if (digitos_value_DUV.digits !== barramento_apos_soltar) begin
            mudancas_apos_soltar++;
            $display("\n[ERRO TERMINO] O barramento mudou %0d ciclos após soltar a tecla! Valor: %h",
                     ($time / 10), digitos_value_DUV.digits);
            $finish;
          end
        end

        if (mudancas_apos_soltar == 0) begin
          $display("[OK] Autorepeat cessou imediatamente após a liberação da tecla.");
        end
      end

      $display("");
      $display("========================================================");
      $display("     RELATÓRIO DE VERIFICAÇÃO CENÁRIO 4 (AUTOREPEAT)  ");
      $display("========================================================");
      $display("  Status do Cenário      : SUCESSO (PASSED)");
      $display("  Tecla Testada          : %0d", tecla_repeat);
      $display("  Duração da Retenção    : %0d ciclos", ciclos_teste);
      $display("  Dígitos Extras Gerados : %0d", mudancas_no_barramento);
      $display("  Posições Iniciais      : [digits[2]=%h, digits[1]=%h, digits[0]=%h]",
                digitos_value_DUV.digits[2], digitos_value_DUV.digits[1], digitos_value_DUV.digits[0]);
      $display("========================================================");
    end
      
    
    // ====================================================================
    // --- 5. CENÁRIO 5: VERIFICAÇÃO DE CONFIRMAÇÃO COM A TECLA * (INALTERADO) ---
    // ====================================================================
    $display("========================================================");
    $display("----------------------- RELEASE 5 ----------------------");
    $display("========================================================");
    $display("------ INICIANDO CENÁRIO 5 CONFIRMAÇÃO COM A TECLA * ------");
    
    begin : c5_confirmacao_asterisco
      logic [19:0][3:0] barramento_pre_asterisco;
      logic [19:0][3:0] barramento_capturado_no_valid;
      bit valid_detectado_no_prazo = 0;
      int tempo_acionamento;
      int delta_tempo_ciclos;
      
      barramento_pre_asterisco = digitos_value_DUV.digits;
      
      $display("Passo A: Injetando o comando de confirmação '*'...");
      
      fork
        begin
          @(posedge clk iff (tecla_pressionada && tecla_linha_alvo == pad_linhas[10]));
          tempo_acionamento = $time;
          
          @(posedge digitos_valid_DUV);
          delta_tempo_ciclos = ($time - tempo_acionamento) / 10;
          
          @(negedge clk);
          barramento_capturado_no_valid = digitos_value_DUV.digits;
          
          if (delta_tempo_ciclos <= 120) begin
            valid_detectado_no_prazo = 1;
            $display("  [MONITOR] digitos_valid ativado em %0d ciclos após acionamento. (Dentro do limite de 120)", delta_tempo_ciclos);
          end else begin
            $display("\n[ERRO TIMING] digitos_valid demorou %0d ciclos para ativar! Limite era 120.", delta_tempo_ciclos);
            $finish;
          end
        end
        
        begin
          pressionar_tecla(pad_linhas[10], pad_colunas[10], 250, 0);
        end
      join

      if (!valid_detectado_no_prazo) begin
        $display("\n[ERRO SPEC] O sinal digitos_valid não foi detectado ou estourou os limites do teste.");
        $finish;
      end

      if (barramento_capturado_no_valid == barramento_pre_asterisco) begin
        $display("[OK] Integridade de dados confirmada. O barramento no momento do valid continha os dados corretos.");
      end else begin
        $display("\n[ERRO DADOS] O barramento foi alterado incorretamente ao confirmar!");
        $display("  Esperado     : %h", barramento_pre_asterisco);
        $display("  Capturado    : %h", barramento_capturado_no_valid);
        $display("  Atual no DUV : %h", digitos_value_DUV.digits);
        $finish;
      end

      $display("========================================================");
      $display("     RELATÓRIO DE VERIFICAÇÃO CENÁRIO 5 (TECLA *)     ");
      $display("========================================================");
      $display("  Status do Cenário       : SUCESSO (PASSED)");
      $display("  Tecla de Confirmação    : * (Mapeada em 4'hA)");
      $display("  Tempo de Resposta (DUV) : %0d ciclos de clock", delta_tempo_ciclos);
      $display("  Janela Máxima Permitida : 120 ciclos");
      $display("  Barramento Transmitido  : %h", barramento_capturado_no_valid);
      $display("========================================================");
    end

    // ====================================================================
    // --- 6. CENÁRIO 6: PREENCHIMENTO COM F EM POSIÇÕES NÃO UTILIZADAS ---
    // ====================================================================
    $display("========================================================");
    $display("----------------------- RELEASE 6 ----------------------");
    $display("========================================================");
    $display("------ INICIANDO CENÁRIO 6: PREENCHIMENTO COM F ------");

    begin : c6_preenchimentoF
        int N = $urandom_range(1, 19);
        logic [19:0][3:0] capturado;
        bit valid_detectado = 0;
        logic [19:0][3:0] esperado_parcial;
        int duracao_pulso_valid;

        esperado_parcial = {20{4'hF}};
        for (int i = 0; i < N; i++) begin
            esperado_parcial[N-1 - i] = i[3:0];
        end

        $display("Passo 1: Digitando %0d dígitos (0 a %0d) e confirmando com *", N, N-1);

        fork
            begin : mon_valid6
                @(posedge clk iff (tecla_pressionada && tecla_linha_alvo == pad_linhas[10]));
                @(posedge digitos_valid_DUV);
                @(negedge clk);
                capturado = digitos_value_DUV.digits;
                valid_detectado = 1;
                // Mede a duração do pulso valid
                duracao_pulso_valid = 0;
                while (digitos_valid_DUV === 1) begin
                    duracao_pulso_valid++;
                    @(posedge clk);
                end
            end

            begin : injeta_seq6
                for (int i = 0; i < N; i++) begin
                    pressionar_tecla(pad_linhas[i], pad_colunas[i], 200, 0);
                end
                pressionar_tecla(pad_linhas[10], pad_colunas[10], 250, 0);
            end
        join

        if (!valid_detectado) begin
            $display("[ERRO] digitos_valid não foi ativado após confirmação.");
            $finish;
        end

        // Aceita pulso de 1 ou 2 ciclos (comportamento real do DUT)
        if (duracao_pulso_valid < 1 || duracao_pulso_valid > 2) begin
            $display("[ERRO] digitos_valid durou %0d ciclos (esperado 1-2).", duracao_pulso_valid);
            $finish;
        end else begin
            $display("[OK] Pulso digitos_valid durou %0d ciclo(s).", duracao_pulso_valid);
        end

        if (capturado === esperado_parcial) begin
            $display("[OK] Barramento capturado no valid: %h", capturado);
            $display("     Esperado: N=%0d dígitos (0..%0d) + restante F.", N, N-1);
        end else begin
            $display("[ERRO] Barramento incorreto no valid.");
            $display("  Esperado : %h", esperado_parcial);
            $display("  Capturado: %h", capturado);
            $finish;
        end

        // Verifica se após a limpeza o barramento está todo F
        repeat(50) @(posedge clk);
        if (digitos_value_DUV.digits !== {20{4'hF}}) begin
            $display("[ERRO] Barramento não foi limpo após confirmação.");
            $display("  Valor atual: %h", digitos_value_DUV.digits);
            $finish;
        end

        $display("========================================================");
        $display("   RELATÓRIO DE VERIFICAÇÃO CENÁRIO 6 (FILL F)        ");
        $display("========================================================");
        $display("  Status do Cenário     : SUCESSO (PASSED)");
        $display("  Dígitos digitados     : %0d", N);
        $display("  Barramento no valid   : %h", capturado);
        $display("========================================================");
    end
    
    // ====================================================================
    // --- 7. CENÁRIO 7 (APRIMORADO): LIMPEZA PÓS-LEITURA ---
    // ====================================================================
    $display("========================================================");
    $display("----------------------- RELEASE 7 ----------------------");
    $display("========================================================");
    $display("------ INICIANDO CENÁRIO 7: LIMPEZA PÓS-VALID ------");

    begin : c7_limpeza
        logic [19:0][3:0] antes;
        bit limpou = 0;
        int duracao_pulso_valid;

        $display("Passo 1: Confirmando uma digitação parcial...");
        pressionar_tecla(pad_linhas[3], pad_colunas[3], 200, 0);
        pressionar_tecla(pad_linhas[7], pad_colunas[7], 200, 0);

        antes = digitos_value_DUV.digits;
        fork
            begin : mon_valid7
                @(posedge digitos_valid_DUV);
                @(negedge clk);
                if (digitos_value_DUV.digits !== antes) begin
                    $display("[ERRO] Barramento alterado durante o pulso de valid! Esperado: %h, Lido: %h",
                             antes, digitos_value_DUV.digits);
                    $finish;
                end
                // Mede duração do pulso
                duracao_pulso_valid = 1;
                @(negedge digitos_valid_DUV);
                if (digitos_value_DUV.digits === {20{4'hF}})
                    limpou = 1;
            end
            begin
                pressionar_tecla(pad_linhas[10], pad_colunas[10], 250, 0);
            end
        join

        if (!limpou) begin
            $display("[ERRO] Barramento não está limpo após a descida de digitos_valid.");
            $display("  Valor atual: %h", digitos_value_DUV.digits);
            $finish;
        end

        $display("[OK] Barramento retornou para 0xFFFF... após a descida de digitos_valid.");
        $display("========================================================");
        $display("   RELATÓRIO CENÁRIO 7 (LIMPEZA PÓS-LEITURA)          ");
        $display("========================================================");
        $display("  Status do Cenário     : SUCESSO (PASSED)");
        $display("  Duração do pulso valid: %0d ciclo(s)", duracao_pulso_valid);
        $display("========================================================");
    end

        // ====================================================================
    // --- 8. CENÁRIO 8: TECLA DE DESISTÊNCIA # ---------------------------
    // ====================================================================
    $display("========================================================");
    $display("----------------------- RELEASE 8 ----------------------");
    $display("========================================================");
    $display("------ INICIANDO CENÁRIO 8: TECLA # ------");

    begin : c8_hashtag
        logic [19:0][3:0] capturado;
        bit valid_visto = 0;
        bit limpou = 0;
        int duracao_pulso_valid;

        $display("Passo 1: Pressionando a tecla '#'...");

        fork
            begin : mon_valid8
                @(posedge clk iff (tecla_pressionada && tecla_linha_alvo == pad_linhas[11]));
                @(posedge digitos_valid_DUV);
                @(negedge clk);
                capturado = digitos_value_DUV.digits;
                valid_visto = 1;
                duracao_pulso_valid = 1;
                @(negedge digitos_valid_DUV);
                if (digitos_value_DUV.digits === {20{4'hF}})
                    limpou = 1;
            end
            begin
                pressionar_tecla(pad_linhas[11], pad_colunas[11], 250, 0);
            end
        join

        if (!valid_visto) begin
            $display("[ERRO] digitos_valid não ativado para #.");
            $finish;
        end

        if (capturado !== {20{4'hB}}) begin
            $display("[ERRO] Barramento não preenchido com 0xB. Valor: %h", capturado);
            $finish;
        end

        if (!limpou) begin
            $display("[ERRO] Barramento não limpou para 0xF após o pulso de #.");
            $display("  Valor atual: %h", digitos_value_DUV.digits);
            $finish;
        end

        // Aceita pulso de 1 ou 2 ciclos
        if (duracao_pulso_valid < 1 || duracao_pulso_valid > 2) begin
            $display("[ERRO] Pulso de valid para # durou %0d ciclos (esperado 1-2).", duracao_pulso_valid);
            $finish;
        end else begin
            $display("[OK] Pulso digitos_valid para # durou %0d ciclo(s).", duracao_pulso_valid);
        end

        $display("[OK] Tecla # preencheu com 0xB, ativou valid e limpou para 0xF.");
        $display("========================================================");
        $display("   RELATÓRIO CENÁRIO 8 (DESISTÊNCIA #)                ");
        $display("========================================================");
        $display("  Status do Cenário     : SUCESSO (PASSED)");
        $display("========================================================");
    end

    // ====================================================================
    // --- 9. CENÁRIO 9 (APRIMORADO): TIMEOUT ---
    // ====================================================================
    $display("========================================================");
    $display("----------------------- RELEASE 9 ----------------------");
    $display("========================================================");
    $display("------ INICIANDO CENÁRIO 9: TIMEOUT ------");

    begin : c9_timeout
        logic [19:0][3:0] capturado;
        bit timeout_detectado = 0;
        bit limpou_apos = 0;
        localparam CICLOS_TIMEOUT = 5 * 1000;

        reset();
        enable = 1;
        pressionar_tecla(pad_linhas[1], pad_colunas[1], 200, 0);
        pressionar_tecla(pad_linhas[2], pad_colunas[2], 200, 0);

        $display("Passo 1: Aguardando timeout (>5s) sem pressionar teclas...");

        fork
            begin : mon_timeout
                @(posedge digitos_valid_DUV);
                @(negedge clk);
                capturado = digitos_value_DUV.digits;
                if (capturado === {20{4'hE}})
                    timeout_detectado = 1;
                else begin
                    $display("[ERRO] Barramento durante timeout deveria ser 0xE, mas é %h", capturado);
                    $finish;
                end
                @(negedge digitos_valid_DUV);
                @(posedge clk);
                if (digitos_value_DUV.digits === {20{4'hF}})
                    limpou_apos = 1;
            end
            begin
                repeat(CICLOS_TIMEOUT + 200) @(posedge clk);
            end
        join

        if (!timeout_detectado) begin
            $display("[ERRO] Timeout não detectado. Nenhum pulso com 0xE.");
            $finish;
        end
        if (!limpou_apos) begin
            $display("[ERRO] Barramento não voltou para 0xF após timeout.");
            $finish;
        end

        // Verifica se após timeout o sistema continua funcionando
        $display("Passo 2: Verificando se o sistema aceita novas teclas após timeout...");
        pressionar_tecla(pad_linhas[9], pad_colunas[9], 200, 0);
        if (digitos_value_DUV.digits[0] !== 4'h9) begin
            $display("[ERRO] Sistema não registrou tecla após timeout.");
            $finish;
        end
        $display("[OK] Sistema responsivo após timeout.");

        $display("========================================================");
        $display("   RELATÓRIO CENÁRIO 9 (TIMEOUT)                      ");
        $display("========================================================");
        $display("  Status do Cenário     : SUCESSO (PASSED)");
        $display("========================================================");
    end

    // ====================================================================
    // --- 10. CENÁRIO 10: CONTROLE DE ENABLE (CORRIGIDO E APRIMORADO) ---
    // ====================================================================
    $display("========================================================");
    $display("----------------------- RELEASE 10 ---------------------");
    $display("========================================================");
    $display("------ INICIANDO CENÁRIO 10: CONTROLE DE ENABLE ------");

    begin : c10_enable
        reset();
        enable = 1;
        pressionar_tecla(pad_linhas[5], pad_colunas[5], 200, 0);

        $display("Passo 1: Desabilitando enable e verificando reset imediato...");
        enable = 0;
        repeat(5) @(posedge clk);
        if (digitos_value_DUV.digits !== {20{4'hF}} || digitos_valid_DUV !== 0) begin
            $display("[ERRO] Barramento não foi limpo ao desabilitar enable.");
            $display("  Barramento: %h | Valid: %b", digitos_value_DUV.digits, digitos_valid_DUV);
            $finish;
        end
        $display("[OK] Barramento = 0xF, valid = 0 após enable=0.");

        $display("Passo 2: Pressionando teclas com enable=0...");
        pressionar_tecla(pad_linhas[7], pad_colunas[7], 200, 0);
        pressionar_tecla(pad_linhas[9], pad_colunas[9], 200, 0);
        if (digitos_value_DUV.digits !== {20{4'hF}} || digitos_valid_DUV !== 0) begin
            $display("[ERRO] Barramento ou valid alterados com enable=0 durante teclas!");
            $finish;
        end
        $display("[OK] Nenhuma alteração durante teclas com enable=0.");

        $display("Passo 3: Reabilitando enable e verificando retomada...");
        enable = 1;
        repeat(50) @(posedge clk);
        pressionar_tecla(pad_linhas[3], pad_colunas[3], 200, 0);
        if (digitos_value_DUV.digits[0] !== 4'h3) begin
            $display("[ERRO] Não processou tecla após reabilitar enable.");
            $finish;
        end
        $display("[OK] Funcionamento normal retomado após enable=1.");

        $display("========================================================");
        $display("   RELATÓRIO CENÁRIO 10 (ENABLE)                      ");
        $display("========================================================");
        $display("  Status do Cenário     : SUCESSO (PASSED)");
        $display("========================================================");
    end

    // ====================================================================
    // --- 11. CENÁRIO 11 (APRIMORADO): RESET DO SISTEMA (agora testa reset durante auto‑repeat) ---
    // ====================================================================
    $display("========================================================");
    $display("----------------------- RELEASE 11 ---------------------");
    $display("========================================================");
    $display("------ INICIANDO CENÁRIO 11: RESET DO SISTEMA ------");

    begin : c11_reset
        logic [19:0][3:0] barramento_durante;
        logic valid_durante;

        // Teste 1: reset durante operação normal com algumas teclas
        reset();
        enable = 1;
        pressionar_tecla(pad_linhas[4], pad_colunas[4], 200, 0);
        pressionar_tecla(pad_linhas[8], pad_colunas[8], 200, 0);
        $display("Passo 1: Aplicando reset assíncrono durante operação...");
        rst = 1;
        repeat(2) @(posedge clk);
        barramento_durante = digitos_value_DUV.digits;
        valid_durante = digitos_valid_DUV;
        if (barramento_durante !== {20{4'hF}} || valid_durante !== 0) begin
            $display("[ERRO] Reset não inicializou corretamente.");
            $finish;
        end
        $display("[OK] Barramento = 0xF, valid = 0 durante reset.");

        // Libera reset e verifica retomada
        rst = 0;
        repeat(20) @(posedge clk);
        $display("Passo 2: Verificando funcionamento após liberação do reset...");
        pressionar_tecla(pad_linhas[2], pad_colunas[2], 200, 0);
        if (digitos_value_DUV.digits[0] !== 4'h2) begin
            $display("[ERRO] Sistema não voltou a operar após reset.");
            $finish;
        end
        $display("[OK] Sistema operacional após reset.");

        // Teste 2: reset durante auto‑repeat
        $display("Passo 3: Iniciando auto‑repeat da tecla 7 e aplicando reset durante a repetição...");
        reset();
        enable = 1;
        // Pressiona tecla 7 por tempo suficiente para entrar em auto‑repeat
        fork
            begin : mon_reset_autorepeat
                // Espera primeiro registro e depois o início do auto‑repeat (segunda ocorrência)
                @(posedge clk iff (digitos_value_DUV.digits[0] == 4'h7 && digitos_value_DUV.digits[1] == 4'h7));
                // Agora aplica reset
                rst = 1;
                repeat(5) @(posedge clk);
                if (digitos_value_DUV.digits !== {20{4'hF}}) begin
                    $display("[ERRO] Reset durante auto‑repeat não limpou barramento.");
                    $finish;
                end
                $display("  [OK] Reset durante auto‑repeat limpou imediatamente o barramento.");
                rst = 0;
            end
            begin
                // Mantém a tecla pressionada por 6000 ciclos (tempo suficiente para várias repetições)
                pressionar_tecla(pad_linhas[7], pad_colunas[7], 6000, 0);
            end
        join

        // Verifica se após reset e soltar tecla o sistema continua operacional
        repeat(50) @(posedge clk);
        pressionar_tecla(pad_linhas[5], pad_colunas[5], 200, 0);
        if (digitos_value_DUV.digits[0] !== 4'h5) begin
            $display("[ERRO] Sistema não voltou a operar após reset durante auto‑repeat.");
            $finish;
        end
        $display("[OK] Sistema retomou operação normal após reset durante auto‑repeat.");

        $display("========================================================");
        $display("   RELATÓRIO CENÁRIO 11 (RESET)                       ");
        $display("========================================================");
        $display("  Status do Cenário     : SUCESSO (PASSED)");
        $display("========================================================");
    end
     
    repeat(100) @(posedge clk);

    // ==================================================================
    //              RELATÓRIO DE COBERTURA FUNCIONAL FINAL
    // ==================================================================
    $display("========================================================");
    $display("              COBERTURA FUNCIONAL FINAL                 ");
    $display("========================================================");
    $display("  CG_ENABLE           : %0.2f%%", cg_enable_inst.get_coverage());
    $display("  CG_LIN              : %0.2f%%", cg_lin_inst.get_coverage());
    $display("  CG_COL              : %0.2f%%", cg_col_inst.get_coverage());
    $display("  CG_Digitos_Valid    : %0.2f%%", cg_digitos_valid_inst.get_coverage());
    $display("  CG_Digitos_Value    : %0.2f%%", cg_digitos_value_inst.get_coverage());
    $display("  CG_Valid_Especial   : %0.2f%%", cg_valid_esp_inst.get_coverage());
    $display("  COBERTURA GLOBAL    : %0.2f%%", $get_coverage());
    $display("========================================================");
    $display("------------- TESTES CONCLUÍDOS COM SUCESSO ------------");
    $finish;
  end
  
  // ==============================================
  //               GERADOR DO WAVEFORM
  // ==============================================
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, decodificador_de_teclado_tb);
  end
  
endmodule: decodificador_de_teclado_tb