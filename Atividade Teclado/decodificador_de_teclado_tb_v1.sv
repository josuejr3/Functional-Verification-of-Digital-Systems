typedef struct packed {
  logic [19:0] [3:0] digits;
} digitosPac_t;

module decodificador_de_teclado_tb;
  
  // ==============================================
  //    Parâmetros de entrada e saída do módulo
  // ==============================================
  logic [3:0] lin_matriz;
  logic [3:0] col_matriz;
  logic enable;
  logic digitos_valid_DUV, digitos_valid_REF;
  digitosPac_t digitos_value_DUV, digitos_value_REF;
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
  //              INSTANCIAÇÃO DO REF
  // ==============================================
  decodificador_de_teclado_ref decode_REF (
    .enable         (enable),
    .lin_matriz     (lin_matriz),
    .col_matriz     (col_matriz),
    .digitos_valid  (digitos_valid_REF),
    .digitos_value  (digitos_value_REF)
  );
  
  // ==============================================
  //    LÓGICA COMBINACIONAL DO TECLADO MATRICIAL
  // ==============================================
  always_comb begin
    if (tecla_pressionada && (lin_matriz == tecla_linha_alvo)) begin
      if (injetar_ruido && ruido_estado) begin
        col_matriz = 4'b1111; // Simula bouncing (chave abrindo no ruído)
      end else begin
        col_matriz = tecla_coluna_alvo; // Curto-circuito perfeito
      end
    end else begin
      col_matriz = 4'b1111; // Nenhuma tecla pressionada ou linha diferente
    end
  end

  // Gerador de ruído aleatório assíncrono independente
  always #2 if (injetar_ruido) ruido_estado = $urandom_range(0,1);

  // ==============================================
  //             GRUPOS DE MONITORAMENTO
  // ==============================================
  covergroup CG_ENABLE @(posedge clk);
    coverpoint enable;
  endgroup
  
  covergroup CG_LIN @(lin_matriz);
    coverpoint lin_matriz;                        
  endgroup
  
  covergroup CG_COL @(col_matriz);
    coverpoint col_matriz;
  endgroup
  
  covergroup CG_Digitos_Valid @(posedge clk); 
    coverpoint digitos_valid_DUV;
  endgroup

  covergroup CG_Digitos_Value @(posedge digitos_valid_DUV); 
    coverpoint digitos_value_DUV.digits[0];
  endgroup
  
  CG_ENABLE        cg_enable_inst         = new;
  CG_LIN           cg_lin_inst            = new;
  CG_COL           cg_col_inst            = new;  
  CG_Digitos_Valid cg_digitos_valid_inst  = new;
  CG_Digitos_Value cg_digitos_value_inst  = new;

  // Monitor Global de Sinais (Log do terminal)
  initial begin
    $monitor("%0t | EN: %b | ROW: %b | COL: %b | Valid_DUV: %b | Value_DUV: %h | Valid_REF: %b | Value_REF: %h",
             $time, enable, lin_matriz, col_matriz, digitos_valid_DUV, digitos_value_DUV.digits, digitos_valid_REF, digitos_value_REF);
  end
  
  // Gerador de Clock de 10ns (#5 em alto, #5 em baixo)
  always #5 clk = ~clk;

  // Task de Reset Global síncrono
  task automatic reset ();
    @(posedge clk); rst = 1;
    repeat(5) @(posedge clk); 
    rst = 0;
  endtask
  
  // ====================================================================
  // TASK DE ESTIMULOS: Injeta as teclas e autovalida o resultado no DUV
  // ====================================================================
  task automatic pressionar_tecla(input [3:0] linha, input [3:0] coluna, input int ciclos_duracao, input bit com_ruido);
    tecla_linha_alvo  = linha;
    tecla_coluna_alvo = coluna;
    
    if (com_ruido) begin
      injetar_ruido     = 1;
      tecla_pressionada = 1;
      repeat(120) @(posedge clk); // Janela inicial isolada de ruído mecânico
      injetar_ruido     = 0;      // Estabiliza os pinos de vez
    end else begin
      tecla_pressionada = 1;
    end
    
    // Aguarda o tempo necessário para passar pelo DEBOUNCE (50 ciclos) + DECODE (1 ciclo)
    repeat(70) @(posedge clk); 
    
    // ------------------------------------------------------------------
    // VERIFICAÇÃO EM TEMPO REAL (Executada no meio da estabilidade da tecla)
    // ------------------------------------------------------------------
    if (enable && !rst) begin
      // Se o modelo de referência capturou o caractere combinacional correto
      if (digitos_valid_REF || (digitos_value_REF.digits[0] != 4'h0)) begin
        
        // Verifica se o valor entrou com sucesso na posição [0] do DUV
        if (digitos_value_DUV.digits[0] !== digitos_value_REF.digits[0]) begin
          $display("\n[ERRO CONSTATADO] O DUV falhou ou shiftou o dígito errado!");
          $display("Tempo da Simulação: %0t ns", $time);
          $display("Esperado pelo REF: %h | Encontrado no DUV[0]: %h", 
                   digitos_value_REF.digits[0], digitos_value_DUV.digits[0]);
          $finish;
        end else begin
          $display("[OK] Dígito %h processado e armazenado com sucesso no DUV!", digitos_value_DUV.digits[0]);
        end
        
      end
    end

    // Completa o restante do tempo que sobrou da duração da tecla
    if (ciclos_duracao > 70) begin
      repeat(ciclos_duracao - 70) @(posedge clk);
    end
    
    // Solta a tecla e deixa as linhas livres para a próxima varredura
    tecla_pressionada = 0;
    repeat(40) @(posedge clk);
  endtask

  // ====================================================================
  //    MAPEAMENTO ALINHADO DO TECLADO MATRICIAL (Bate com o DUV)
  // ====================================================================
  // Índice:          0        1        2        3        4        5        6        7        8        9       10(*)    11(#)
  logic [3:0] pad_linhas  [12] = '{4'b1110, 4'b0111, 4'b0111, 4'b0111, 4'b1011, 4'b1011, 4'b1011, 4'b1101, 4'b1101, 4'b1101, 4'b1110, 4'b1110};
  logic [3:0] pad_colunas [12] = '{4'b1011, 4'b0111, 4'b1011, 4'b1101, 4'b0111, 4'b1011, 4'b1101, 4'b0111, 4'b1011, 4'b1101, 4'b0111, 4'b1101};

  // ==============================================
  //              BLOCO PRINCIPAL DE TESTES
  // ==============================================
  initial begin
    int tecla_sorteada;
    int duracao_sorteada;
    bit ruido_sorteado;

    // Inicialização das condições iniciais de simulação
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
    repeat (25) begin
      tecla_sorteada   = $urandom_range(0, 9);      // Sorteia apenas teclas numéricas de 0 a 9
      duracao_sorteada = $urandom_range(120, 300); // Garante tempo acima dos 50 ciclos do debounce
      ruido_sorteado   = $urandom_range(0, 1);      // Ativa/desativa ruído dinamicamente
      
      $display("[RANDOM] Pressionando Tecla: %0d | Duração Estável: %0d ciclos | Com Ruído: %0b", 
               tecla_sorteada, duracao_sorteada, ruido_sorteado);
               
      pressionar_tecla(pad_linhas[tecla_sorteada], pad_colunas[tecla_sorteada], duracao_sorteada, ruido_sorteado);
    end

    // --- 2. TESTE ALEATÓRIO DE REPETIÇÃO AUTOMÁTICA ---
    tecla_sorteada = $urandom_range(0, 9);
    $display("Testando Autorepetição Longa com a Tecla: %0d...", tecla_sorteada);
    pressionar_tecla(pad_linhas[tecla_sorteada], pad_colunas[tecla_sorteada], 4500, 0); 

    // --- 3. TESTE DE CONFIRMAÇÃO (*) ---
    // Como vimos, esta ação fará o seu DUV transicionar para VALID_KEY e disparar digitos_valid para 1!
    $display("Enviando tecla de confirmação * para validar o barramento...");
    pressionar_tecla(pad_linhas[10], pad_colunas[10], 150, 0); 
    
    repeat(100) @(posedge clk);

    $display("------ TESTE ALEATÓRIO CONCLUÍDO COM SUCESSO ------");
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