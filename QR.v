`timescale 1ns/1ps

module qr_top #(
    parameter DATA_W = 12, // 外部輸入矩陣 A 的位元寬度 (12-bit)
    parameter INT_W  = 28, // 內部定點數運算寬度 (28-bit)
    parameter FRAC_W = 12  // 內部小數點保護位元寬度 (12-bit)
)(
    input  wire clk,
    input  wire rst_n,

    // 外部控制與資料輸入介面
    input  wire              start_qr,   
    input  wire [DATA_W-1:0] a_din_0,    
    input  wire [DATA_W-1:0] a_din_1,    
    input  wire [DATA_W-1:0] a_din_2,    
    input  wire [DATA_W-1:0] a_din_3,   
    input  wire              a_valid_in, 

    // 輸出介面
    output reg               done,       
    output wire [INT_W-1:0]  r_out_0,    
    output wire [INT_W-1:0]  r_out_1,
    output wire [INT_W-1:0]  r_out_2,
    output wire [INT_W-1:0]  r_out_3,
    output wire [INT_W-1:0]  q_out_0,    
    output wire [INT_W-1:0]  q_out_1,
    output wire [INT_W-1:0]  q_out_2,
    output wire [INT_W-1:0]  q_out_3,
    output wire              out_valid   
);

    // ========================================================
    // 1. 內部 FIFO 宣告與外部資料寫入邏輯 (Bit Alignment)
    // ========================================================
    reg signed [INT_W-1:0] fifo_a [0:3][0:3]; 
    reg [1:0] wr_ptr; // 寫入指標，用來記錄現在寫到第幾個 Row
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 2'd0;
        end else if (a_valid_in) begin
            // 【DSP 核心升級】: 符號擴充 + 小數點補零
            // 28-bit = 4-bit (符號擴充) + 12-bit (原始資料) + 12-bit (小數補零)
            fifo_a[0][wr_ptr] <= { {4{a_din_0[DATA_W-1]}}, a_din_0, 12'd0 };
            fifo_a[1][wr_ptr] <= { {4{a_din_1[DATA_W-1]}}, a_din_1, 12'd0 };
            fifo_a[2][wr_ptr] <= { {4{a_din_2[DATA_W-1]}}, a_din_2, 12'd0 };
            fifo_a[3][wr_ptr] <= { {4{a_din_3[DATA_W-1]}}, a_din_3, 12'd0 };
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // ========================================================
    // FSM 狀態與暫存器宣告
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
    // 第一段：狀態暫存器 (State Register)
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= ST_IDLE;
        else        state <= next_state;
    end

    // ========================================================
    // 第二段：下一狀態邏輯 (Next State Logic)
    // ========================================================
    always @(*) begin
        next_state = state; 
        case (state)
            ST_IDLE:  if (start_qr)        next_state = ST_FEED;
            ST_FEED:  if (run_cnt == 8'd19) next_state = ST_WAIT;
            ST_WAIT:  if (run_cnt == 8'd35) next_state = ST_FLUSH;
            ST_FLUSH: if (run_cnt == 8'd39) next_state = ST_IDLE;
            default: next_state = ST_IDLE;
        endcase
    end

    // ========================================================
    // 第三段：資料與計數器更新 (Datapath Registers)
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run_cnt <= 8'd0;
            tick_4  <= 2'd0;
            done    <= 1'b0;
            for (i=0; i<8; i=i+1) fed_cnt[i] <= 3'd0;
        end else begin
            done <= 1'b0; 
            case (state)
                ST_IDLE: begin
                    run_cnt <= 8'd0;
                    tick_4  <= 2'd0;
                    for (i=0; i<8; i=i+1) fed_cnt[i] <= 3'd0;
                end
                ST_FEED: begin
                    run_cnt <= run_cnt + 1'b1;
                    tick_4  <= tick_4 + 1'b1; 
                    for (i=0; i<8; i=i+1) begin
                        if (tick_4 == i[1:0] && run_cnt >= i && fed_cnt[i] < 4) begin
                            fed_cnt[i] <= fed_cnt[i] + 1'b1;
                        end
                    end
                end
                ST_WAIT: begin
                    run_cnt <= run_cnt + 1'b1;
                end
                ST_FLUSH: begin
                    run_cnt <= run_cnt + 1'b1;
                    if (run_cnt == 8'd38) done <= 1'b1; 
                end
            endcase
        end
    end

    // ========================================================
    // 第四段：輸出與接線邏輯 (Output Logic)
    // ========================================================
    always @(*) begin
        pe_start_bottom = 8'b00000000;
        flush_en        = (state == ST_FLUSH);
        
        for (i=0; i<8; i=i+1) pe_yin_bottom[i] = 0; // 去除常數寫死，適應 28-bit

        if (state == ST_FEED) begin
            for (i=0; i<8; i=i+1) begin
                if (tick_4 == i[1:0] && run_cnt >= i && fed_cnt[i] < 4) begin
                    pe_start_bottom[i] = 1'b1;
                    
                    if (i < 4) begin
                        pe_yin_bottom[i] = fifo_a[i][fed_cnt[i]];
                    end else begin
                        // 【DSP 核心升級】: 1.0 的真實定點數值 = 1 左移 FRAC_W 位
                        pe_yin_bottom[i] = (fed_cnt[i] == (i - 4)) ? (1 << FRAC_W) : 0;
                    end
                end
            end
        end
    end

    // ========================================================
    // 4. Systolic Array 二維網格接線宣告
    // ========================================================
    wire signed [INT_W-1:0] grid_y     [0:4][0:7]; 
    wire [3:0]              grid_dir   [0:3][0:8]; 
    wire                    grid_valid [0:4][0:7];

    genvar c;
    generate
        for (c = 0; c < 8; c = c + 1) begin : bottom_inputs
            assign grid_y[0][c]     = pe_yin_bottom[c];
            assign grid_valid[0][c] = pe_start_bottom[c]; 
        end
    endgenerate

    // ========================================================
    // 5. 自動生成 PE 陣列並完成接線
    // ========================================================
    genvar r, col;
    generate
        for (r = 0; r < 4; r = r + 1) begin : row_gen
            for (col = 0; col < 8; col = col + 1) begin : col_gen
                
                if (col == r) begin
                    cordic_vectoring_pe #( .INT_W(INT_W) ) pe_vec (
                        .clk(clk), .rst_n(rst_n), .flush_en(flush_en),
                        .start(grid_valid[r][col]), .y_in(grid_y[r][col]),      
                        .y_out(grid_y[r+1][col]), .dir_out(grid_dir[r][col+1]),  
                        .valid_out(grid_valid[r+1][col]) 
                    );
                end 
                else if (col > r) begin
                    cordic_rotation_pe #( .INT_W(INT_W) ) pe_rot (
                        .clk(clk), .rst_n(rst_n), .flush_en(flush_en),
                        .start(grid_valid[r][col]), .y_in(grid_y[r][col]), .dir_in(grid_dir[r][col]),    
                        .y_out(grid_y[r+1][col]), .dir_out(grid_dir[r][col+1]),  
                        .valid_out(grid_valid[r+1][col]) 
                    );
                end 
                else begin : elevator_inst
                    reg signed [INT_W-1:0] elevator_y;
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n)             elevator_y <= 0;
                        else if (flush_en)      elevator_y <= grid_y[r][col];
                    end
                    assign grid_y[r+1][col]     = elevator_y;
                    assign grid_valid[r+1][col] = 1'b0; 
                end
            end
        end
    endgenerate

    // ========================================================
    // 6. 頂端輸出擷取
    // ========================================================
    assign out_valid = flush_en;
    
    assign r_out_0 = grid_y[4][0];
    assign r_out_1 = grid_y[4][1];
    assign r_out_2 = grid_y[4][2];
    assign r_out_3 = grid_y[4][3];

    assign q_out_0 = grid_y[4][4];
    assign q_out_1 = grid_y[4][5];
    assign q_out_2 = grid_y[4][6];
    assign q_out_3 = grid_y[4][7];

endmodule