`timescale 1ns/1ps

module cordic_rotation_pe #(
    parameter INT_W = 28 // 預設為 28-bit
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   flush_en, 
    input  wire                   start,      
    input  wire signed [INT_W-1:0] y_in,    
    input  wire [3:0]             dir_in,   

    output reg  signed [INT_W-1:0] y_out,   
    output reg  [3:0]             dir_out,    
    output reg                    valid_out   
);

    localparam IDLE   = 3'd0; 
    localparam CAL0   = 3'd1; 
    localparam CAL1   = 3'd2; 
    localparam CAL2   = 3'd3; 
    localparam NORM   = 3'd4; 

    reg [2:0] state; 
    reg signed [INT_W-1:0] x_reg;
    reg signed [INT_W-1:0] y_reg;
    reg flush_d1;

    reg signed [INT_W-1:0] x_c [0:4];
    reg signed [INT_W-1:0] y_c [0:4];
    reg [3:0] current_shift; 
    integer i;

    always @(*) begin
        x_c[0] = x_reg;
        y_c[0] = y_reg; 
        
        case (state)
            CAL0: current_shift = 4'd0;
            CAL1: current_shift = 4'd4;
            CAL2: current_shift = 4'd8;
            default: current_shift = 4'd0;
        endcase      

        for (i = 0; i < 4; i = i + 1) begin
            if (dir_in[i] == 1'b1) begin 
                x_c[i+1] = x_c[i] + (y_c[i] >>> (current_shift + i));
                y_c[i+1] = y_c[i] - (x_c[i] >>> (current_shift + i));
            end else begin
                x_c[i+1] = x_c[i] - (y_c[i] >>> (current_shift + i));
                y_c[i+1] = y_c[i] + (x_c[i] >>> (current_shift + i));
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_reg     <= 0; 
            y_reg     <= 0;
            state     <= IDLE;
            y_out     <= 0;
            dir_out   <= 0;
            valid_out <= 0;
            flush_d1  <= 0;
        end else begin
            flush_d1  <= flush_en;
            valid_out <= 1'b0; 

            if (flush_en) begin
                if (!flush_d1) begin
                    y_out <= x_reg; 
                    x_reg <= 0;     
                end else begin
                    y_out <= y_in;  
                end
                state <= IDLE;
            end else begin
                case (state)
                    IDLE: begin 
                        if (start) begin
                            y_reg <= y_in; 
                            state <= CAL0; 
                        end
                    end

                    CAL0, CAL1, CAL2: begin 
                        x_reg   <= x_c[4];
                        y_reg   <= y_c[4];
                        dir_out <= dir_in; 
                        
                        if (state == CAL2)
                            state <= NORM;
                        else
                            state <= state + 1'b1;
                    end

                    NORM: begin 
                        x_reg     <= (x_reg >>> 1) + (x_reg >>> 3) - (x_reg >>> 6) - (x_reg >>> 9);
                        y_out     <= (y_reg >>> 1) + (y_reg >>> 3) - (y_reg >>> 6) - (y_reg >>> 9); 
                        valid_out <= 1'b1; 
                        
                        if (start) begin
                            y_reg <= y_in;
                            state <= CAL0;
                        end else begin
                            state <= IDLE;
                        end
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule