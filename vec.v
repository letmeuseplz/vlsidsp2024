module cordic_vectoring_pe #(
    parameter INT_W = 16  
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,      
    input  wire signed [INT_W-1:0] y_in,   

    output reg  signed [INT_W-1:0] y_out,   
    output reg  [3:0]           dir_out,    
    output reg                  valid_out   
);

    // ==========================================
    // 狀態機定義 (FSM States)
    // ==========================================
    localparam IDLE   = 3'd0; 
    localparam CAL0 = 3'd1; 
    localparam CAL1 = 3'd2; 
    localparam CAL2 = 3'd3; 
    localparam NORM   = 3'd4; 

    reg [2:0] state, next_state;

    
    reg signed [INT_W-1:0] x_reg; 
    reg signed [INT_W-1:0] y_reg;

    // ==========================================
    // 
    // ==========================================
    reg signed [INT_W-1:0] x_c[0:4];
    reg signed [INT_W-1:0] y_c[0:4];
    reg [3:0] dir_c; 
    reg [3:0] current_shift; 
    
    integer i;

    always @(*) begin

        x_c[0] = x_reg;
        y_c[0] = y_reg; 
        dir_c  = 4'b0000;
        
      
        case (state)
            CAL0: current_shift = 4'd0;
            CAL1: current_shift = 4'd4;
            CAL2: current_shift = 4'd8;
            default: current_shift = 4'd0;
        endcase

        
        for (i = 0; i < 4; i = i + 1) begin
            
            if (y_c[i][INT_W-1] == 1'b0) begin 
                
                dir_c[i] = 1'b1; 
                x_c[i+1] = x_c[i] + (y_c[i] >>> (current_shift + i));
                y_c[i+1] = y_c[i] - (x_c[i] >>> (current_shift + i));
            end else begin
               
                dir_c[i] = 1'b0; 
                x_c[i+1] = x_c[i] - (y_c[i] >>> (current_shift + i));
                y_c[i+1] = y_c[i] + (x_c[i] >>> (current_shift + i));
            end
        end
    end

    // ==========================================
    //
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_reg     <= 0; 
            y_reg     <= 0;
            state     <= IDLE;
            y_out     <= 0;
            dir_out   <= 0;
            valid_out <= 0;
        end else begin
            
            valid_out <= 1'b0; 

            case (state)
                IDLE: begin
                    if (start) begin
                        y_reg <= y_in;     
                        state <= CAL0;
                        
                    end
                end

                CAL0: begin
                    x_reg   <= x_c[4];
                    y_reg   <= y_c[4];
                    dir_out <= dir_c;   
                    state   <= CAL1;
                end

                CAL1: begin
                    x_reg   <= x_c[4];
                    y_reg   <= y_c[4];
                    dir_out <= dir_c;   
                    state   <= CAL2;
                end

                CAL2: begin
                    x_reg   <= x_c[4];
                    y_reg   <= y_c[4];
                    dir_out <= dir_c;   
                    state   <= NORM;
                end

                NORM: begin
                    // near 0.607
                    x_reg     <= (x_reg >>> 1) + (x_reg >>> 3) - (x_reg >>> 6) - (x_reg >>> 9);
                    y_out     <= (y_reg >>> 1) + (y_reg >>> 3) - (y_reg >>> 6) - (y_reg >>> 9); 
                    
                    valid_out <= 1'b1;     
                    state     <= IDLE;     
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule