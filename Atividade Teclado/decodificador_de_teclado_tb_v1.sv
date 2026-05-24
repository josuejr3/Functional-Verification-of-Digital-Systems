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
      
      ignore_bins confirmacao = {4'hA};
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

    // variaveis teste 2
   	logic [3:0] fila_esperada [$];
    logic [3:0] v_esperado;
    int time_press;
    int c_ruido;
    
    
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
      tecla_sorteada   = $urandom_range(0, 10);
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

    // --- 1.1 TESTE DIRECIONADO PARA COBERTURA TOTAL DE VALORES ---
    $display("Forçando a cobertura de todos os dígitos no Covergroup...");
    enable = 1;
    for (int i = 0; i <= 9; i++) begin
      // Pressiona o dígito 'i'
      pressionar_tecla(pad_linhas[i], pad_colunas[i], 200, 0); 
      // Pressiona o '*' para disparar o valid e salvar o dígito na cobertura
      pressionar_tecla(pad_linhas[10], pad_colunas[10], 250, 0); 
    end
    
    // ------------------------------------------------------------------
    // RELATÓRIO DE COBERTURA — CENÁRIO 1.1
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
    
    
    // --- 2. TESTE DO SHIFT DO BARRAMENTO
    $display("\------ INICIANDO CENÁRIO 2: VERIFICAÇÃO DE SHIFT DO BARRAMENTO ------");
    reset();
    enable = 1;
    fila_esperada.delete();
    
    // Passo 1: Digitar de 0-9 2 vezes
    // Passo A: Digitar a sequência de 0 a 9 duas vezes consecutivas (Preenche as 20 posições)
    $display("Passo A: Preenchendo o barramento digitando de 0 a 9 duas vezes consecutivas...");
    for (int r = 0; r < 2; r++) begin
      for (int i = 0; i <= 9; i++) begin
        pressionar_tecla(pad_linhas[i], pad_colunas[i], 200, 0);
        fila_esperada.push_back(i); // Guarda no espelho do TB
        
        // Validação em tempo real a cada tecla inserida durante o preenchimento
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
    
    $display("Passo B: Inserindo mais 30 dígitos aleatórios continuamente e testando o descarte...");
    repeat (30) begin
      tecla_sorteada = $urandom_range(0, 9);
      pressionar_tecla(pad_linhas[tecla_sorteada], pad_colunas[tecla_sorteada], 200, 0);
      
      fila_esperada.push_back(tecla_sorteada);
      if (fila_esperada.size() > 20) begin
        void'(fila_esperada.pop_front()); // Descarta o mais antigo da nossa fila de controle
      end

      // Verificação completa das 20 posições simultaneamente
      for (int k = 0; k < 20; k++) begin
        v_esperado = fila_esperada[19 - k]; // Fila fixa em 20 elementos agora
        if (digitos_value_DUV.digits[k] !== v_esperado) begin
          $display("\n[ERRO SHIFT - TRANSBORDAMENTO] O algoritmo de descarte falhou ou gerou efeito circular!");
          $display("Tempo: %0t ns | Posição [%0d] esperava %h, mas DUV contém %h", $time, k, v_esperado, digitos_value_DUV.digits[k]);
          $display("Estado atual do barramento DUV: %h", digitos_value_DUV.digits);
          $finish;
        end
      end
    end
    $display("[SUCESSO] Cenário 2 concluído! O barramento manteve estritamente os últimos 20 dígitos na ordem correta.");
    
    
    // ==================================================================
    // RELATÓRIO DE VERIFICAÇÃO DETALHADO — CENÁRIO 2 (SHIFT REGISTER)
    // ==================================================================
    $display("");
    $display("========================================================");
    $display("   RELATÓRIO DE VERIFICAÇÃO — CENÁRIO 2 (SHIFT REG)     ");
    $display("========================================================");
    $display("  Status do Cenário      : SUCESSO (PASSED)");
    $display("  Capacidade Máxima      : 20 dígitos verificados");
    $display("  Estímulos Injetados    : 50 teclas (20 preenchimento + 30 estouro)");
    $display("  Algoritmo de Descarte  : OK (Sem efeito circular ou travamento)");
    $display("--------------------------------------------------------");
    
    // Imprime o barramento do DUV do mais antigo (digits[19]) para o mais novo (digits[0])
    $write("  Barramento no DUV      : [ ");
    for (int k = 19; k >= 0; k--) begin
      $write("%h ", digitos_value_DUV.digits[k]);
    end
    $display("]");
    
    // Imprime a fila de controle do TB na mesma ordem para comparação visual
    $write("  Espelho de Controle(TB): [ ");
    for (int k = 0; k < 20; k++) begin
      $write("%h ", fila_esperada[k]);
    end
    $display("]");
    $display("========================================================");
    $display("");
    
    // ====================================================================
    // --- 3. CENÁRIO 3: VERIFICAÇÃO DE DEBOUNCE (FILTRAGEM DE RUÍDO) -----
    // ====================================================================
    $display("\n------ INICIANDO CENÁRIO 3: VERIFICAÇÃO DE DEBOUNCE ------");
    reset();
    enable = 1;
    
    begin : c3_debounce
      logic [19:0][3:0] barramento_inicial;
      logic [19:0][3:0] barramento_pos_ruido;
      logic [19:0][3:0] barramento_final;
      int digitos_inseridos_durante_ruido = 0;
      int digitos_inseridos_apos_estabilizar = 0;
      int tecla_teste = 5; // Vamos testar com a tecla '5'
      
      // Captura o estado limpo pós-reset
      barramento_inicial = digitos_value_DUV.digits;
      
      $display("Passo A: Iniciando bouncing mecânico (ruído) por 100 ciclos de clock...");
      tecla_linha_alvo  = pad_linhas[tecla_teste];
      tecla_coluna_alvo = pad_colunas[tecla_teste];
      tecla_pressionada = 1;
      injetar_ruido     = 1; // Ativa o gerador assíncrono do TB
      
      // Mantém o ruído gerando transições aleatórias por exatamente 100 clocks
      repeat(100) @(posedge clk);
      
      // Checa se o DUV ignorou o ruído enquanto ele acontecia
      barramento_pos_ruido = digitos_value_DUV.digits;
      if (barramento_pos_ruido !== barramento_inicial) begin
        $display("\n[ERRO DEBOUNCE] O circuito aceitou uma tecla instável durante o período de ruído!");
        $finish;
      end
      $display("  [OK] Nenhuma tecla espúria foi registrada durante os 100 ciclos de oscilação.");

      $display("Passo B: Estabilizando o sinal da tecla (fim do ruído) e aguardando validação...");
      injetar_ruido = 0; // Sinal estabiliza no valor correto da tecla
      
      // Aguarda o tempo necessário para o DUV processar o debounce estável e fazer o shift (130 ciclos)
      repeat(CICLOS_ATE_SHIFT) @(posedge clk);
      
      // Verifica se a tecla entrou corretamente após a estabilização
      barramento_final = digitos_value_DUV.digits;
      
      // Conta quantas modificações aconteceram na posição inicial do barramento
      if (barramento_final[0] == tecla_teste) begin
        $display("  [OK] Tecla %0d reconhecida com sucesso após o período de estabilização.", tecla_teste);
      end else begin
        $display("\n[ERRO DEBOUNCE] O sistema ignorou a tecla legítima após o ruído cessar!");
        $display("  Esperado em digits[0]: %h | Obtido: %h", tecla_teste, barramento_final[0]);
        $finish;
      end
      
      // Garante que APENAS UMA tecla entrou (as outras posições devem continuar em reset hF)
      for (int i = 1; i < 20; i++) begin
        if (barramento_final[i] !== 4'hF) begin
          $display("\n[ERRO DEBOUNCE] Multiplos registros detectados! O debounce deixou passar múltiplos repiques.");
          $finish;
        end
      end
      
      // Finaliza o acionamento da tecla
      tecla_pressionada = 0;
      repeat(40) @(posedge clk);

      // ==================================================================
      // RELATÓRIO DE VERIFICAÇÃO DETALHADO — CENÁRIO 3 (DEBOUNCE)
      // ==================================================================
      $display("");
      $display("========================================================");
      $display("     RELATÓRIO DE VERIFICAÇÃO — CENÁRIO 3 (DEBOUNCE)    ");
      $display("========================================================");
      $display("  Status do Cenário       : SUCESSO (PASSED)");
      $display("  Duração do Bouncing     : 100 ciclos de clock (Injetado)");
      $display("  Comportamento do Filtro : Filtragem Total (Ignorou oscilações)");
      $display("  Teclas Válidas Retidas  : 1 única tecla (Dígito %0d)", tecla_teste);
      $display("  Barramento Resultante   : %h", digitos_value_DUV.digits);
      $display("========================================================");
      $display("");
    end
      
    // ====================================================================
    // --- 4. CENÁRIO 4: VERIFICAÇÃO DE REPETIÇÃO AUTOMÁTICA (AUTOREPEAT) ---
    // ====================================================================
    $display("\n------ INICIANDO CENÁRIO 4: VERIFICAÇÃO DE AUTOREPEAT ------");
    reset();
    enable = 1;
    injetar_ruido = 0; // Isolamento contra ruído

    begin : c4_autorepeat
      int mudancas_no_barramento = 0;
      bit c4_terminou = 0;
      int tecla_repeat = 3; // Força uma tecla conhecida para análise visual
      logic [19:0][3:0] barramento_anterior;
      
      // 5500 ciclos são suficientes: 130 (inicial) + 2000 (2s) + 1000 (1s) + 1000 (1s) + folga
      int ciclos_teste = 5500; 
      
      $display("Passo A: Mantendo a tecla %0d pressionada por %0d ciclos...", tecla_repeat, ciclos_teste);
      
      // Armazena o estado inicial do barramento antes do teste estendido
      barramento_anterior = digitos_value_DUV.digits;

      fork
        // Thread 1: Monitora modificações no barramento em tempo real
        begin
          // Espera passar a primeira inserção padrão para não contar duas vezes
          repeat(150) @(posedge clk);
          barramento_anterior = digitos_value_DUV.digits;

          while (!c4_terminou) begin
            @(posedge clk);
            // Se o barramento mudou enquanto a tecla está travada, foi um estalo do Autorepeat!
            if (digitos_value_DUV.digits != barramento_anterior) begin
              mudancas_no_barramento++;
              $display("  [MONITOR] Autorepetição detectada em %0t ns! Barramento atualizado: %h", $time, digitos_value_DUV.digits);
              barramento_anterior = digitos_value_DUV.digits;
            end
          end
        end
        
        // Thread 2: Executa o pressionamento longo na sua task
        begin
          pressionar_tecla(pad_linhas[tecla_repeat], pad_colunas[tecla_repeat], ciclos_teste, 0);
          c4_terminou = 1;
        end
      join

      // VERIFICAÇÃO DO COMPORTAMENTO DO DUV
      $display("\nAnálise final do barramento DUV: %h", digitos_value_DUV.digits);
      
      if (mudancas_no_barramento >= 2) begin
        $display("[OK] O recurso de autorepetição adicionou %0d dígitos extras por tempo de retenção.", mudancas_no_barramento);
      end else begin
        $display("\n[ERRO AUTOREPEAT] A tecla ficou retida mas o barramento só registrou %0d repetições extras.", mudancas_no_barramento);
        $finish;
      end

      // ==================================================================
      // RELATÓRIO DE VERIFICAÇÃO DETALHADO — CENÁRIO 4 (AUTOREPEAT)
      // ==================================================================
      $display("");
      $display("========================================================");
      $display("     RELATÓRIO DE VERIFICAÇÃO — CENÁRIO 4 (AUTOREPEAT)  ");
      $display("========================================================");
      $display("  Status do Cenário      : SUCESSO (PASSED)");
      $display("  Tecla Testada          : %0d", tecla_repeat);
      $display("  Duração da Retenção    : %0d ciclos", ciclos_teste);
      $display("  Dígitos Extras Gerados : %0d", mudancas_no_barramento);
      $display("  Posições Iniciais      : [digits[2]=%h, digits[1]=%h, digits[0]=%h]", 
                digitos_value_DUV.digits[2], digitos_value_DUV.digits[1], digitos_value_DUV.digits[0]);
      $display("========================================================");
      $display("");
    end
      
    
    // ====================================================================
    // --- 5. CENÁRIO 5: VERIFICAÇÃO DE CONFIRMAÇÃO COM A TECLA * --------
    // ====================================================================
    $display("\n------ INICIANDO CENÁRIO 5: CONFIRMAÇÃO COM A TECLA * ------");
    
    begin : c5_confirmacao_asterisco
      logic [19:0][3:0] barramento_pre_asterisco;
      logic [19:0][3:0] barramento_capturado_no_valid;
      bit valid_detectado_no_prazo = 0;
      int tempo_acionamento;
      int delta_tempo_ciclos;
      
      // Captura o estado atual do barramento antes de apertar a tecla de confirmação
      barramento_pre_asterisco = digitos_value_DUV.digits;
      
      $display("Passo A: Injetando o comando de confirmação '*'...");
      
      fork
        // Thread 1: Monitora o sinal digitos_valid_DUV e mede o tempo de resposta
        begin
          // Aguarda o momento exato em que o DUV começa a receber o estímulo físico
          @(posedge clk iff (tecla_pressionada && tecla_linha_alvo == pad_linhas[10]));
          tempo_acionamento = $time;
          
          // Espera o pulso de validação do DUV
          @(posedge digitos_valid_DUV);
          delta_tempo_ciclos = ($time - tempo_acionamento) / 10; // Cada ciclo tem 10ns
          
          // Amostragem segura na borda de descida (meio do ciclo) para evitar Race Condition
          @(negedge clk);
          barramento_capturado_no_valid = digitos_value_DUV.digits;
          
          // Validação do teto máximo de 120 ciclos exigido pelo roteiro
          if (delta_tempo_ciclos <= 120) begin
            valid_detectado_no_prazo = 1;
            $display("  [MONITOR] digitos_valid ativado em %0d ciclos após acionamento. (Dentro do limite de 120)", delta_tempo_ciclos);
          end else begin
            $display("\n[ERRO TIMING] digitos_valid demorou %0d ciclos para ativar! Limite era 120.", delta_tempo_ciclos);
            $finish;
          end
        end
        
        // Thread 2: Executa fisicamente a pressão da tecla '*' via task padrão
        begin
          pressionar_tecla(pad_linhas[10], pad_colunas[10], 250, 0);
        end
      join

      // VERIFICAÇÃO 1: O sinal de validação subiu?
      if (!valid_detectado_no_prazo) begin
        $display("\n[ERRO SPEC] O sinal digitos_valid não foi detectado ou estourou os limites do teste.");
        $finish;
      end

      // VERIFICAÇÃO 2: Os dados digitados anteriormente foram preservados no disparo do valid?
      if (barramento_capturado_no_valid == barramento_pre_asterisco) begin
        $display("[OK] Integridade de dados confirmada. O barramento no momento do valid continha os dados corretos.");
      end else begin
        $display("\n[ERRO DADOS] O barramento foi alterado incorretamente ao confirmar!");
        $display("  Esperado     : %h", barramento_pre_asterisco);
        $display("  Capturado    : %h", barramento_capturado_no_valid);
        $display("  Atual no DUV : %h", digitos_value_DUV.digits);
        $finish;
      end

      // ==================================================================
      // RELATÓRIO DE VERIFICAÇÃO DETALHADO — CENÁRIO 5 (CONFIRMAÇÃO)
      // ==================================================================
      $display("");
      $display("========================================================");
      $display("     RELATÓRIO DE VERIFICAÇÃO — CENÁRIO 5 (TECLA *)     ");
      $display("========================================================");
      $display("  Status do Cenário       : SUCESSO (PASSED)");
      $display("  Tecla de Confirmação    : * (Mapeada em 4'hA)");
      $display("  Tempo de Resposta (DUV) : %0d ciclos de clock", delta_tempo_ciclos);
      $display("  Janela Máxima Permitida : 120 ciclos");
      $display("  Barramento Transmitido  : %h", barramento_capturado_no_valid);
      $display("========================================================");
      $display("");
    end
     
    repeat(100) @(posedge clk);

    // ==================================================================
    // COLE O SEU BLOCO DE RELATÓRIO DE COBERTURA AQUI (ANTES DO $finish)
    // ==================================================================
    $display("");
    $display("========================================================");
    $display("  COBERTURA FUNCIONAL FINAL");
    $display("========================================================");
    $display("  CG_ENABLE        : %0.2f%%", cg_enable_inst.get_coverage());
    $display("  CG_LIN           : %0.2f%%", cg_lin_inst.get_coverage());
    $display("  CG_COL           : %0.2f%%", cg_col_inst.get_coverage());
    $display("  CG_Digitos_Valid : %0.2f%%", cg_digitos_valid_inst.get_coverage());
    $display("  CG_Digitos_Value : %0.2f%%", cg_digitos_value_inst.get_coverage());
    $display("  COBERTURA GLOBAL : %0.2f%%", $get_coverage());
    $display("========================================================");
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