module decodificador_de_teclado_tb;
  
  // ==============================================
  //    Parâmetros de entrada e saída do módulo
  // ==============================================
  
  logic [3:0] lin_matriz, col_matriz;
  logic enable;
  logic digitos_valid_DUV, digitos_valid_REF;
  senhaPac_t digitos_value_DUV, digitos_value_REF;
  bit clk;
  logic rst;
  
  // ==============================================
  //              INSTANCIAÇÃO DO DUV
  // ==============================================
  
  decodificador_de_teclado decode_DUV (
    .clk				(clk),
    .rst				(rst),
    .enable				(enable),
    .lin_matriz			(lin_matriz),
    .col_matriz			(col_matriz),
    .digitos_valid		(digitos_valid_DUV),
    .digitos_value		(digitos_value_DUV)
  );
  
  // ==============================================
  //              INSTANCIAÇÃO DO REF
  // ==============================================
  
  decodificador_de_teclado_ref decode_REF (
    .clk				(clk),
    .rst				(rst),
    .enable				(enable),
    .lin_matriz			(lin_matriz),
    .col_matriz			(col_matriz),
    .digitos_valid		(digitos_valid_REF),
    .digitos_value		(digitos_value_REF)
  );
  
  // ==============================================
  //           GRUPOS DE MONITORAMENTO
  // ==============================================
  
  covergroup CG_ENABLE @(enable);							// Monitora o sinal enable
    coverpoint enable;
  endgroup
  
  covergroup CG_LIN @(lin_matriz);							// Monitora as linhas
    coverpoint lin_matriz;						
  endgroup
  
  covergroup CG_COL @(col_matriz);							// Monitora as colunas
    coverpoint col_matriz;
  endgroup
  
  covergroup CG_Digitos_Valid @(digitos_valid_DUV); 		// Monitora o digitos_valid
    coverpoint digitos_valid_DUV;
  endgroup
  
  covergroup CG_Digitos_Value @(digitos_value_DUV); 		// Monitora o digitos_value
    coverpoint digitos_value_DUV;
  endgroup
  
  // ==============================================
  //                     MONITOR
  // ==============================================
  
  initial begin
    $monitor("%0t ENABLE: %b | ROW: %b | COL: %b | Valid_DUV: %b | Valid_REF: %b | Value_DUV: %h",
                 $time, enable, lin_matriz, col_matriz, digitos_valid_DUV, digitos_valid_REF, digitos_value_DUV);
  end
    
  
  initial begin
    clk = 0;
    rst = 0;
  end
  
  always #5 clk = ~clk;
  
  // ==============================================
  //             BLOCO PRINCIPAL DE TESTES
  // ==============================================
  initial begin
    
    CG_ENABLE			cg_enable_inst			= new;		// Instância do monitoramento do enable
    CG_LIN				cg_lin_inst				= new;		// Instância do monitoramento da linha
    CG_COL				cg_col_inst				= new;  	// Instância do monitoramento da coluna
    CG_Digitos_valid 	cg_digitos_valid_inst 	= new;		// Instância do monitoramento do digitos valid
    CG_Digitos_value 	cg_digitos_value_inst   = new;		// Instância do monitoramento do digitos value
    
    
    rst = 1;												// Reset do sistema
    repeat(2) @(posedge clk);								
    rst = 0;												// Reset desativado
    repeat(2) @(posedge clk);
    
    
    while ((cg_enable_inst.get_coverage() < 100) || 
           (cg_lin_inst.get_coverage() < 100) || 
           (cg_col_inst.get_coverage() < 100) || 
           (cg_digitos_valid_inst.get_coverage() < 100) || 
           (cg_digitos_value_inst.get_coverage() < 100)) begin
      
      
      int col_selected = $urandom(0, 4);					// Seleciona uma coluna (0,1,2,3) 
      enable = $urandom_range(0,1);							// Seleciona se o enable está ativo (1) ou desativado (0)
      
      if (col_selected < 4 && lin_matriz !== 4'bxxxx) begin	// Executa se a coluna é (0,1,2,3) e a linha é conhecida
		// 
      end else begin
        //
      end
      
      repeat (2) @(posedge clk);							// Tempo para o DUV e o REF responderem
      
      $display("CG_ENABLE: %.2f%% | CG_LIN: %.2f%% | CG_COL: %.2f%% | CG_Digitos_Valid: %.2f%% | CG_Digitos_Value: %.2f%%", 
               cg_enable_inst.get_coverage(), cg_lin_inst.get_coverage(), cg_col_inst.get_coverage(), 
               cg_digitos_valid_inst.get_coverage(), cg_digitos_value_inst.get_coverage())
      
      if ((digitos_valid_REF !== digitos_valid_DUV) || 		// Condicional para verificar o valid e o value
          (digitos_value_REF !== digitos_value_DUV)) begin
        	$display("\n[ERRO] Diferença encontrada entre DUV e REF!");
        	$display("LINHA (DUV): %b | COLUNA (TB): %b", lin_matriz, col_matriz);
        	$display("REF -> Valid: %b, Value: %h", digitos_valid_REF, digitos_value_REF);
        	$display("DUV -> Valid: %b, Value: %h\n", digitos_valid_DUV, digitos_value_DUV);
       		$finish;
      end
    end

    $display("------ TESTE CONCLUÍDO COM SUCESSO ------");
  	$finish;
  end 
  
  // ==============================================
  //                    WAVEFORM
  // ==============================================
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, decodificador_de_teclado_tb);
  end
  
endmodule: decodificador_de_teclado_tb