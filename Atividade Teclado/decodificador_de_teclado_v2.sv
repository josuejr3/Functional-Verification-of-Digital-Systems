module decodificador_de_teclado (
    input  logic         clk,           
    input  logic         rst,           
    input  logic         enable,        
    input  logic [3:0]   col_matriz,   
    output logic [3:0]   lin_matriz,    
    output digitosPac_t digitos_value, 
    output logic         digitos_valid  
);


    localparam int DEBOUNCE_TIME = 100;    
    localparam int HOLD_2S_TIME  = 2000;  
    localparam int HOLD_1S_TIME  = 1000;  
    localparam int TIMEOUT_5S    = 5000;  

    typedef enum logic [3:0] {
        ST_INIT,
        ST_SCAN,
        ST_DEBOUNCE,
        ST_PROCESS,
        ST_HOLD,
        ST_VALID_PULSE,
        ST_TIMEOUT_PULSE,
        ST_CLEAR
    } state_t;

    state_t state;

    // Registradores internos
    logic [12:0] count_timeout;
    logic [11:0] count_action;
    logic [11:0] hold_target;
    logic        has_input;
    
    logic [3:0]  saved_col;
    logic [3:0]  saved_lin;
    logic [3:0]  key_decoded;

    logic [3:0]  col_sync_reg1;
    logic [3:0]  col_matriz_sync;

    logic [3:0]  lin_pipe1;
    logic [3:0]  lin_delayed;

    logic [2:0]  scan_prescaler;


    function automatic logic [3:0] decode_key(input logic [3:0] row, input logic [3:0] col);
        case ({row, col})
            8'b0111_0111: return 4'h1; // Tecla 1
            8'b0111_1011: return 4'h2; // Tecla 2
            8'b0111_1101: return 4'h3; // Tecla 3
            8'b1011_0111: return 4'h4; // Tecla 4
            8'b1011_1011: return 4'h5; // Tecla 5
            8'b1011_1101: return 4'h6; // Tecla 6
            8'b1101_0111: return 4'h7; // Tecla 7
            8'b1101_1011: return 4'h8; // Tecla 8
            8'b1101_1101: return 4'h9; // Tecla 9
            8'b1110_1011: return 4'h0; // Tecla 0
            8'b1110_0111: return 4'hA; // Tecla *
            8'b1110_1101: return 4'hB; // Tecla #
            default:      return 4'hF; // Nenhuma válida
        endcase
    endfunction
	 

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        col_sync_reg1        <= 4'b1111;
        col_matriz_sync      <= 4'b1111;
        lin_pipe1            <= 4'b0111;
        lin_delayed          <= 4'b0111;
        
        state                <= ST_INIT;
        lin_matriz           <= 4'b0111;
        digitos_value.digits <= {20{4'hF}}; 
        digitos_valid        <= 1'b0;
        
        count_timeout        <= '0;
        count_action         <= '0;
        hold_target          <= '0;
        has_input            <= 1'b0;
        saved_col            <= 4'b1111;
        saved_lin            <= 4'b1111;
        key_decoded          <= 4'hF;
        scan_prescaler       <= '0;
    end 
    else if (enable) begin 
        col_sync_reg1   <= col_matriz;
        col_matriz_sync <= col_sync_reg1;

        lin_pipe1   <= lin_matriz;
        lin_delayed <= lin_pipe1;

        digitos_valid <= 1'b0;

        case (state)
            ST_INIT: begin
                digitos_value.digits <= {20{4'hF}}; 
                lin_matriz           <= 4'b0111;
                has_input            <= 1'b0;
                scan_prescaler       <= '0;
                state                <= ST_SCAN;
            end

            ST_SCAN: begin
                if (has_input && (count_timeout >= TIMEOUT_5S)) begin
                    digitos_value.digits <= {20{4'hE}}; 
                    state                <= ST_TIMEOUT_PULSE;
                end 
                else if (col_matriz_sync != 4'b1111) begin
                    saved_col    <= col_matriz_sync;
                    saved_lin    <= lin_delayed; 
                    count_action <= '0;
                    state        <= ST_DEBOUNCE;
                end 
                else begin
                    if (has_input) count_timeout <= count_timeout + 1'b1;

                    scan_prescaler <= scan_prescaler + 1'b1;
                    if (scan_prescaler == 3'd4) begin
                        scan_prescaler <= '0;
                        case (lin_matriz)
                            4'b0111: lin_matriz <= 4'b1011;
                            4'b1011: lin_matriz <= 4'b1101;
                            4'b1101: lin_matriz <= 4'b1110;
                            4'b1110: lin_matriz <= 4'b0111;
                            default: lin_matriz <= 4'b0111;
                        endcase
                    end
                end
            end

            ST_DEBOUNCE: begin
                 if (col_matriz_sync != saved_col) begin
                      state <= ST_SCAN; 
                 end else begin
                      count_action <= count_action + 1'b1;
                      if (count_action >= DEBOUNCE_TIME) begin
                            key_decoded <= decode_key(saved_lin, saved_col); 
                            state       <= ST_PROCESS;
                      end
                 end
            end
            
            ST_PROCESS: begin
                if (key_decoded == 4'hA) begin
                    state <= ST_VALID_PULSE; 
                end 
                else if (key_decoded == 4'hB) begin
                    digitos_value.digits <= {20{4'hB}};
                    state                <= ST_VALID_PULSE; 
                end 
                else if (key_decoded != 4'hF) begin
                    digitos_value.digits <= {digitos_value.digits[18:0], key_decoded};
                    has_input            <= 1'b1;          
                    count_timeout        <= '0;            
                    count_action         <= '0;
                    hold_target          <= HOLD_2S_TIME;  
                    state                <= ST_HOLD;
                end else begin
                    state <= ST_SCAN;
                end
            end

            ST_HOLD: begin
                if ((col_matriz_sync == 4'b1111) || (col_matriz_sync != saved_col)) begin
                    state         <= ST_SCAN;
                    count_timeout <= '0; 
                end else begin
                    if (key_decoded != 4'hA && key_decoded != 4'hB) begin
                        count_action <= count_action + 1'b1;
                        if (count_action >= hold_target) begin
                            digitos_value.digits <= {digitos_value.digits[18:0], key_decoded};
                            count_action         <= '0;
                            hold_target          <= HOLD_1S_TIME; 
                        end
                    end
                end
            end

            ST_VALID_PULSE, ST_TIMEOUT_PULSE: begin
                digitos_valid <= 1'b1;     
                state         <= ST_CLEAR; 
            end

            ST_CLEAR: begin
                digitos_value.digits <= {20{4'hF}}; 
                has_input            <= 1'b0;
                count_timeout        <= '0;
                count_action         <= '0;
                
                if (col_matriz_sync != 4'b1111) begin
                    state <= ST_HOLD;
                end else begin
                    state <= ST_SCAN;
                end
            end

            default: state <= ST_INIT;
        endcase
    end
end
endmodule