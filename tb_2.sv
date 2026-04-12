`timescale 1ns/1ps

module tb;

  logic clk, rst;
  logic push_button, infravermelho;
  logic led, saida;
  
  always #1 clk = ~clk;  // clock de 2ns período (500 MHz)

  // DUT
  controladora #(
    .DEBOUNCE_P(300),
    .SWITCH_MODE_MIN_T(5000),
    .AUTO_SHUTDOWN_T(30000)
  ) dut (
    .clk(clk),
    .rst(rst),
    .infravermelho(infravermelho),
    .push_button(push_button),
    .led(led),
    .saida(saida)
  );
  
  parameter int SEED = 1001;
  parameter int MIN = 0;
  parameter int MAX = 10350;
  
  // Classe responsável por criar números aleatórios
  class RandomNumber;
    
    // Cria um número binário entre [0 - 16383]
    randc bit [13:0] number; 
    
    // Define os valores limites
    int min, max;
    
    // Construtor da classe 
    function new(input int min, input int max);
      this.min = min;
      this.max = max;
    endfunction
    
    // Regra que define o sorteio dos números no intervalo min:max
    constraint rangenumber { number inside {[min:max]}; }    
  endclass
  
  // Task que aguarda uma quantidade de ciclos acontecer
  task automatic wait_cycles(int cycles);
    repeat (cycles) @(posedge clk);
  endtask
  
  // Task de pressionamento do push button
  task automatic press_button(int cycles);
    push_button = 1;
    wait_cycles(cycles);
    push_button = 0;
    wait_cycles(10);
  endtask
  
  // Task que faz o reset do sistema baseado na quantidade de ciclos
  task automatic reset(input int cycles);
    rst = 1;
    wait_cycles(cycles);
    rst = 0;
  endtask
  
  // Task que incrementa o número do teste e checa as condições
  task automatic check_condition(string description, logic expected, logic actual);
    static int number_test = 1;
    if (expected !== actual) begin
      $error("[%0t] - [TESTE - %d] %s: expected %b, got %b", $time, number_test, description, expected, actual);
    end else begin
      $display("[%0t] - [TESTE - %d] %s: OK (expected %b)", $time, number_test, description, expected);
    end
	number_test++;
    #10;
  endtask
  
  
  // A Task que faz a troca de modos 
  task automatic switch_mode(input int pulses, input string description = "");
    static int test_number = 1;
    logic expected_led;
    
    if (pulses > 5310 && pulses < 10350)
      expected_led = ~led;
    else 
      expected_led = led;
    
    $display("[%0t] TESTE %2d: %s", $time, test_number, description);
    $display("-----------------------------------------------------------------------------------");
    
    press_button(pulses);
    
	// 4. Comparação dos leds
    if (led === expected_led) begin
      $display("RESULTADO: [PASSOU] | Pulsos: %0d | LED: %b | Output: %b | LED Esperado: %b", pulses, led, saida, expected_led);
    end else begin
      $error("RESULTADO: [FALHOU] | Enviado: %0d | LED: %b | Output: %b | LED Esperado: %b", pulses, led, saida, expected_led);
    end
    $display("-----------------------------------------------------------------------------------");
    test_number++;
    
    
  endtask
  
  
  
  
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
  end
  
  // Setando sinais principais
  initial begin
    rst = 0;
    clk = 0;
    infravermelho = 0;
    push_button = 0;
  end
  
  
  RandomNumber random_n;
  
  initial begin
    
   	logic led_expected;
    logic output_expected;
    
    // Sistema Resetado - (Desligado Automático) 
    $display("[%0t] Início da Simulação", $time);
    $display("[%0t] Aplicando Reset...", $time);
    reset(10);
    $display("[%0t] Reset finalizado.", $time);
    
    led_expected = 0;
    output_expected = 0;
    
    // Teste RESET do sistema - LAMP_DES_AUTO
    check_condition("RESET", led_expected, led);
    check_condition("RESET", output_expected, saida);
    
    $srandom(SEED);
    random_n = new(MIN, MAX);
    
    $display("-----------------------------------------------------------------------------------");
    repeat (30) begin
      if (random_n.randomize()) begin
        $display("NÚMERO SORTEADO: %d", random_n.number);
        $display("ESTADO ATUAL: %s", dut.sub_1.state.name());
        switch_mode(random_n.number);
      end else begin
        $display("ERRO AO RANDOMIZAR!");
      end
  
    end
    
    
    

	$finish;
  end
  
  
  

endmodule
