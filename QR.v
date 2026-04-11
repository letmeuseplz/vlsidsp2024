`timescale 1ns/1ps

module qr_top #(
    parameter DATA_W = 8,
    parameter INT_W  = 12,
    parameter Q_FRAC = 10  // Q 路徑小數點 (Q2.10)
)
(
    input  wire clk,
    input  wire rst_n,


    input  wire              start_qr,   
    input  wire [DATA_W-1:0] a_din_0,    
    input  wire [DATA_W-1:0] a_din_1,    
    input  wire [DATA_W-1:0] a_din_2,    
    input  wire [DATA_W-1:0] a_din_3,   
    input  wire              a_valid_in, 


    output reg               done,       
    output reg  [INT_W-1:0]  r_out_0,    
    output reg  [INT_W-1:0]  r_out_1,
    output reg  [INT_W-1:0]  r_out_2,
    output reg  [INT_W-1:0]  r_out_3,
    output reg  [INT_W-1:0]  q_out_0,    
    output reg  [INT_W-1:0]  q_out_1,
    output reg  [INT_W-1:0]  q_out_2,
    output reg  [INT_W-1:0]  q_out_3,
    output reg               out_valid   
);

    // ========================================================
    // FSM 
    // ========================================================
    localparam ST_IDLE  = 3'd0;
    localparam ST_FEED  = 3'd1; 
    localparam ST_WAIT  = 3'd2; 
    localparam ST_FLUSH = 3'd3; 
    
    reg [2:0] state, next_state;

    reg [7:0] run_cnt;
    reg [1:0] tick_4;           
    reg [2:0] fed_cnt [0:7];    
    integer i;
    
    reg       flush_en;
    reg [7:0] pe_start_bottom;              
    reg signed [INT_W-1:0] pe_yin_bottom [0:7]; 

    // ========================================================
    // fifo sim
    // ========================================================
    reg signed [INT_W-1:0] fifo_a [0:3][0:3]; 
    reg [1:0] wr_ptr; 
    reg       fifo_ready; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= 2'd0;
            fifo_ready <= 1'b0;
            for (i=0; i<4; i=i+1) begin
                for (integer j=0; j<4; j=j+1) fifo_a[i][j] <= 0;
            end
        end else if (a_valid_in) begin
            fifo_a[0][wr_ptr] <= { {2{a_din_0[DATA_W-1]}}, a_din_0, 2'd0 };
            fifo_a[1][wr_ptr] <= { {2{a_din_1[DATA_W-1]}}, a_din_1, 2'd0 };
            fifo_a[2][wr_ptr] <= { {2{a_din_2[DATA_W-1]}}, a_din_2, 2'd0 };
            fifo_a[3][wr_ptr] <= { {2{a_din_3[DATA_W-1]}}, a_din_3, 2'd0 };
            if (wr_ptr == 2'd3) fifo_ready <= 1'b1;
            wr_ptr <= wr_ptr + 1'b1;
        end else if (state == ST_FEED) begin
            fifo_ready <= 1'b0; 
        end
    end

    // ========================================================
    // 2. FSM 
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= ST_IDLE;
        else        state <= next_state;
    end

    always @(*) begin
        next_state = state; 
        case (state)
            ST_IDLE:  if (start_qr && fifo_ready) next_state = ST_FEED;
            ST_FEED:  if (run_cnt == 8'd19)       next_state = ST_WAIT;
            ST_WAIT:  if (run_cnt == 8'd41)       next_state = ST_FLUSH;
            ST_FLUSH: if (run_cnt == 8'd47)       next_state = ST_IDLE;
            default:  next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run_cnt <= 8'd0; tick_4 <= 2'd0; done <= 1'b0;
            for (i=0; i<8; i=i+1) fed_cnt[i] <= 3'd0;
        end else begin
            done <= 1'b0; 
            case (state)
                ST_IDLE: begin
                    run_cnt <= 8'd0; tick_4 <= 2'd0;
                    for (i=0; i<8; i=i+1) fed_cnt[i] <= 3'd0;
                end
                ST_FEED: begin
                    run_cnt <= run_cnt + 1'b1; tick_4 <= tick_4 + 1'b1; 
                    for (i=0; i<8; i=i+1) begin
                        if (tick_4 == i[1:0] && run_cnt >= i && fed_cnt[i] < 4) 
                            fed_cnt[i] <= fed_cnt[i] + 1'b1;
                    end
                end
                ST_WAIT:  run_cnt <= run_cnt + 1'b1;
                ST_FLUSH: begin
                    run_cnt <= run_cnt + 1'b1;
                    if (run_cnt == 8'd47) done <= 1'b1; 
                end
            endcase
        end
    end

    // ========================================================
    // input
    // ========================================================
    always @(*) begin
        pe_start_bottom = 8'b00000000;
        flush_en        = (state == ST_FLUSH);
        for (i=0; i<8; i=i+1) pe_yin_bottom[i] = 0;
        if (state == ST_FEED) begin
            for (i=0; i<8; i=i+1) begin
                if (tick_4 == i[1:0] && run_cnt >= i && fed_cnt[i] < 4) begin
                    pe_start_bottom[i] = 1'b1;
                    if (i < 4) pe_yin_bottom[i] = fifo_a[i][fed_cnt[i]];
                    else       pe_yin_bottom[i] = (fed_cnt[i] == (i - 4)) ? (1 << Q_FRAC) : 0;
                end
            end
        end
    end
    // ========================================================
    // systolic array
    // ========================================================
    wire signed [INT_W-1:0] grid_y [0:4][0:7]; 
    wire [3:0] grid_dir [0:3][0:8]; 
    wire grid_valid [0:4][0:7];

    genvar c_idx;
    generate
        for (c_idx = 0; c_idx < 8; c_idx = c_idx + 1) begin : bottom_inputs
            assign grid_y[0][c_idx]     = pe_yin_bottom[c_idx];
            assign grid_valid[0][c_idx] = pe_start_bottom[c_idx]; 
        end
    endgenerate

    genvar r_idx, col_idx;
    generate
        for (r_idx = 0; r_idx < 4; r_idx = r_idx + 1) begin : row_gen
            for (col_idx = 0; col_idx < 8; col_idx = col_idx + 1) begin : col_gen
                if (col_idx == r_idx) begin
                    cordic_vectoring_pe #( .INT_W(INT_W) ) pe_vec (
                        .clk(clk), .rst_n(rst_n), .flush_en(flush_en),
                        .start(grid_valid[r_idx][col_idx]), .y_in(grid_y[r_idx][col_idx]),      
                        .y_out(grid_y[r_idx+1][col_idx]), .dir_out(grid_dir[r_idx][col_idx+1]),  
                        .valid_out(grid_valid[r_idx+1][col_idx]) 
                    );
                end else if (col_idx > r_idx) begin
                    cordic_rotation_pe #( .INT_W(INT_W) ) pe_rot (
                        .clk(clk), .rst_n(rst_n), .flush_en(flush_en),
                        .start(grid_valid[r_idx][col_idx]), .y_in(grid_y[r_idx][col_idx]), .dir_in(grid_dir[r_idx][col_idx]),    
                        .y_out(grid_y[r_idx+1][col_idx]), .dir_out(grid_dir[r_idx][col_idx+1]),  
                        .valid_out(grid_valid[r_idx+1][col_idx]) 
                    );
                end else begin : elevator_inst
                    reg signed [INT_W-1:0] elevator_y;
                    reg elevator_v;
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n) begin elevator_y <= 0; elevator_v <= 0; end
                        else begin elevator_y <= grid_y[r_idx][col_idx]; elevator_v <= grid_valid[r_idx][col_idx]; end
                    end
                    assign grid_y[r_idx+1][col_idx]     = elevator_y;
                    assign grid_valid[r_idx+1][col_idx] = elevator_v; 
                end
            end
        end
    endgenerate

    // ========================================================
    // output
    // ========================================================

    wire raw_valid_any = |{grid_valid[4][0], grid_valid[4][1], grid_valid[4][2], grid_valid[4][3],
                           grid_valid[4][4], grid_valid[4][5], grid_valid[4][6], grid_valid[4][7]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            r_out_0 <= 0; r_out_1 <= 0; r_out_2 <= 0; r_out_3 <= 0;
            q_out_0 <= 0; q_out_1 <= 0; q_out_2 <= 0; q_out_3 <= 0;
        end else begin
   
            if (state == ST_FLUSH) begin
                out_valid <= raw_valid_any;
                r_out_0 <= grid_y[4][0];
                r_out_1 <= grid_y[4][1];
                r_out_2 <= grid_y[4][2];
                r_out_3 <= grid_y[4][3];
                q_out_0 <= grid_y[4][4];
                q_out_1 <= grid_y[4][5];
                q_out_2 <= grid_y[4][6];
                q_out_3 <= grid_y[4][7];
            end else begin
                out_valid <= 1'b0;
               
                r_out_0 <= 0; r_out_1 <= 0; r_out_2 <= 0; r_out_3 <= 0;
                q_out_0 <= 0; q_out_1 <= 0; q_out_2 <= 0; q_out_3 <= 0;
            end
        end
    end

endmodule