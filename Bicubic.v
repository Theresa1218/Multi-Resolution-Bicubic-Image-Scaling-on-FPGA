module Bicubic (
    input CLK,
    input RST,
    input [6:0] V0,
    input [6:0] H0,
    input [4:0] SW,
    input [4:0] SH,
    input [5:0] TW,
    input [5:0] TH,
    output reg  DONE,
    output        bram0_en,
    output [31:0] bram0_addr,
    input  [31:0] bram0_rdata,
    output        bram1_en,
    output [3:0]  bram1_we,      
    output [31:0] bram1_addr,
    output [31:0] bram1_wdata);

    localparam
        init = 0,
        start = 1,
        cubic1_1 = 2,
        cubic1_2 = 3,
        cubic1_3 = 4,
        cubic1_4 = 5,
        cubic1_5 = 6,
        cubic2_1 = 7,
        cubic2_2 = 8,
        cubic2_3 = 9,
        cubic2_4 = 10,
        cubic2_5 = 11,
        cubic3_1 = 12,
        cubic3_2 = 13,
        cubic3_3 = 14,
        cubic3_4 = 15,
        cubic3_5 = 16,
        cubic4_1 = 17,
        cubic4_2 = 18,
        cubic4_3 = 19,
        cubic4_4 = 20,
        cubic4_5 = 21,
        cubic5_1 = 22,
        cubic5_2 = 23,
        coincide = 24,
        coincide_W_1 = 25,
        coincide_W_2 = 26,
        coincide_W_3 = 27,
        coincide_W_4 = 28,
        coincide_H_1 = 29,
        coincide_H_2 = 30,
        coincide_H_3 = 31,
        coincide_H_4 = 32,
        coincide_H_5 = 33,
        coincide_H_6 = 34,
        write_sram = 35,
        check = 36,
        wait_rom = 37,
        wait_rom_plus = 38,
        div_w_wait = 39,
        div_h_wait = 40,
        cubic5_mul1 = 41,
        cubic5_mul2 = 42,
        cubic5_mul3 = 43,
        coincide_H_mul1 = 44,
        coincide_H_mul2 = 45,
        coincide_H_mul3 = 46,
        cubic_h_mul1 = 47,
        cubic_h_mul2 = 48,
        cubic_h_mul3 = 49,
        cubic_h_mul3_add = 50,
        cubic_h_add3 = 51,
        cubic5_mul3_add = 52,
        cubic5_add3 = 53,
        coincide_H_mul3_add = 54,
        coincide_H_add3 = 55,
        done_state = 56,
        length = 100;


    reg [5:0] state, next_state;
    reg [47:0] STW, STH, cur_W, cur_H;
    reg [5:0] TW_count, TH_count;
    reg signed [8:0] a, b, c, d, f1, f2, f3, f4;
    reg signed [76:0] tmp;
    reg signed [11:0] c5_A;
    reg signed [11:0] c5_B;
    reg signed [8:0]  c5_C;
    reg signed [8:0]  c5_D;
    reg signed [20:0] c5_t;
    reg signed [33:0] c5_p1;
    reg signed [55:0] c5_p2;
    reg signed [76:0] c5_p3;
    reg signed [48:0] c5_p3_H;
    reg        [47:0] c5_p3_L;
    reg [1:0] h_row;
    reg sram_wen;
    reg [7:0] result;

    reg         div_start;
    reg [47:0]  div_dividend;
    reg [5:0]   div_divisor;
    wire        div_busy;
    wire        div_done;
    wire [47:0] div_quotient;
    divider_48_6 u_divider (
        .clk      (CLK),
        .rst      (RST),
        .start    (div_start),
        .dividend (div_dividend),
        .divisor  (div_divisor),

        .busy     (div_busy),
        .done     (div_done),
        .quotient (div_quotient)
    );

    wire [7:0] index;
    wire [6:0] h_int = cur_H[26:20];
    wire [6:0] w_int = cur_W[26:20];
    wire [13:0] h_ext = {7'd0,h_int};
    wire [13:0] w_ext = {7'd0,w_int};
    wire [13:0] h_x100 = (h_ext << 6) + (h_ext << 5) + (h_ext << 2);
    wire [13:0] h_prev_x100 = h_x100 - 14'd100;
    reg [13:0] rom_addr;
    reg [13:0] ram_addr;
    
     // BRAM 0 
    assign bram0_en = 1'b1; 
    assign bram0_addr = {16'b0, rom_addr[13:2], 2'b00};
    wire [1:0] read_byte_offset = rom_addr[1:0];
    assign index = (read_byte_offset == 2'b00) ? bram0_rdata[7:0]   :
                   (read_byte_offset == 2'b01) ? bram0_rdata[15:8]  :
                   (read_byte_offset == 2'b10) ? bram0_rdata[23:16] :
                                                 bram0_rdata[31:24] ;

    // BRAM 1 
    assign bram1_en = 1'b1;
    wire [15:0] current_ram_idx = (TH_count * TW) + TW_count;
    assign bram1_addr = {16'b0, current_ram_idx[13:2], 2'b00};
    assign bram1_wdata = {result, result, result, result};
    wire [1:0] write_byte_offset = current_ram_idx[1:0];
    reg [3:0] we_mask;

    //ImgROM u_ImgROM (.Q(index), .CLK(CLK), .CEN(1'b0), .A(rom_addr));
    //ResultSRAM u_ResultSRAM (.Q(), .CLK(CLK), .CEN(1'b0), .WEN(sram_wen), .A(ram_addr), .D(result));
    assign bram1_we = we_mask; 
    always @(*) begin
        if (state == write_sram) begin 
            case(write_byte_offset)
                2'b00: we_mask = 4'b0001;
                2'b01: we_mask = 4'b0010;
                2'b10: we_mask = 4'b0100;
                2'b11: we_mask = 4'b1000;
            endcase
        end else begin
            we_mask = 4'b0000;
        end
    end
    
    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            sram_wen <= 1;
            DONE <= 0;
            state <= init;
            TW_count <= 0;
            TH_count <= 0;
            div_start    <= 0;
            div_dividend <= 0;
            div_divisor  <= 0;
            h_row <= 0;
        end
        else begin
            state <= next_state;
            div_start <= 1'b0;
            case (state)
                init: begin
                    //STW <= ({21'd0, SW - 1} << 20) / (TW - 1);
                    //STH <= ({21'd0, SH - 1} << 20) / (TH - 1);
                    div_dividend <= {23'd0,(SW - 1'b1),20'd0};
                    div_divisor <= TW - 1'b1;
                    div_start <= 1'b1;

                    cur_W <= {21'd0, H0, 20'd0};
                    cur_H <= {21'd0, V0, 20'd0};
                    DONE <= 0;
                    TW_count <= 0;
                    TH_count <= 0;
                end
                div_w_wait: begin
                    if (div_done) begin
                        STW <= div_quotient;
                        div_dividend <= {23'd0, (SH - 1'b1), 20'd0};
                        div_divisor <= TH - 1'b1;
                        div_start <= 1'b1;
                    end
                end
                div_h_wait: begin
                    if (div_done) begin
                        STH <= div_quotient;
                    end
                end
                start: begin
                    if (cur_W[19:0] == 0) begin
                        if (cur_H[19:0] == 0) begin
                            //rom_addr <= ((cur_H >>> 20) * length) + (cur_W >>> 20);
                            rom_addr <= h_x100 + w_ext;
                            //cur_w <= cur_W >>> 8;
                            //cur_h <= cur_H >>> 8;
                        end
                        else begin
                            //rom_addr <= (((cur_H >>> 20) - 1) * length) + (cur_W >>> 20);
                            rom_addr <= h_prev_x100 + w_ext;
                            //cur_w <= cur_W >>> 8;
                            //cur_h <= (cur_H >>> 8) - 1;
                        end
                    end
                    else if (cur_H[19:0] == 0) begin
                        //rom_addr <= ((cur_H >>> 20) * length) + ((cur_W >>> 20) - 1);
                        rom_addr <= h_x100 + w_ext - 14'd1;
                        //cur_w <= (cur_W >>> 8) - 1;
                        //cur_h <= cur_H >>> 8;
                    end
                    else begin
                        //rom_addr <= (((cur_H >>> 20) - 1) * length) + ((cur_W >>> 20) - 1);
                        rom_addr <= h_prev_x100 + w_ext - 14'd1;
                        //cur_w <= (cur_W >>> 8) - 1;
                        //cur_h <= (cur_H >>> 8) - 1;
                    end
                end
                wait_rom: begin
                    rom_addr <= rom_addr + 1;
                end
                wait_rom_plus: begin
                    rom_addr <= rom_addr + length;
                end
                cubic1_1: begin
                    a <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic1_2: begin
                    b <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic1_3: begin
                    c <= $signed({1'b0, index});
                    //rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic1_4: begin
                    //tmp <= ((((((-a) + 3*b - 3*c + $signed({1'b0, index})) * cur_W[19:0])) + ((2*a - 5*b + 4*c - $signed({1'b0, index})) << 20)) * cur_W[19:0] + (((-a) + c) << 40)) * cur_W[19:0] + (b << 61) + (80'sd1 << 60);
                    c5_A <= -$signed(a) + 3*$signed(b) - 3*$signed(c) + $signed({1'b0,index}); 
                    c5_B <= 2*$signed(a) - 5*$signed(b) + 4*$signed(c) - $signed({1'b0,index}); 
                    c5_C <= -$signed(a) + $signed(c); c5_D <= $signed(b); 
                    c5_t <= $signed({1'b0,cur_W[19:0]}); h_row <= 2'd0; 
                    rom_addr <= rom_addr - 3 + length;
                end
                cubic_h_mul1: begin 
                    c5_p1 <= ($signed(c5_A)*$signed(c5_t)) + ($signed({{22{c5_B[11]}},c5_B}) <<< 20); 
                end
                cubic_h_mul2: begin 
                    c5_p2 <= ($signed(c5_p1) * $signed(c5_t)) + ($signed({{47{c5_C[8]}}, c5_C}) <<< 40);
                end
                cubic_h_mul3: begin
                    c5_p3_H <= $signed(c5_p2[55:28]) * $signed({1'b0, c5_t[19:0]});
                    c5_p3_L <= $unsigned(c5_p2[27:0]) * $unsigned(c5_t[19:0]);
                end
                cubic_h_mul3_add: begin
                    c5_p3 <= ($signed({{28{c5_p3_H[48]}}, c5_p3_H}) <<< 28) + $signed({29'd0, c5_p3_L});
                end
                cubic_h_add3: begin
                    tmp <= $signed(c5_p3) + ($signed({{68{c5_D[8]}}, c5_D}) <<< 61) + (77'sd1 <<< 60);
                end
                cubic1_5: begin
                    if (tmp[76]) f1 <= 8'd0;
                    else if (tmp > (75'sd255 << 61)) f1 <= 8'd255;
                    else f1 <= tmp[68:61];
                    rom_addr <= rom_addr + 1;
                    //cur_w <= (cur_W >> 8) - 1;
                    //cur_h <= (cur_H >> 8);
                end
                cubic2_1: begin
                    a <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic2_2: begin
                    b <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic2_3: begin
                    c <= $signed({1'b0, index});
                    //cur_w <= cur_w + 1;
                end
                cubic2_4: begin
                    //tmp <= ((((((-a) + 3*b - 3*c + $signed({1'b0, index})) * cur_W[19:0])) + ((2*a - 5*b + 4*c - $signed({1'b0, index})) << 20)) * cur_W[19:0] + (((-a) + c) << 40)) * cur_W[19:0] + (b << 61) + (80'sd1 << 60);
                    c5_A <= -$signed(a) + 3*$signed(b) - 3*$signed(c) + $signed({1'b0,index}); 
                    c5_B <= 2*$signed(a) - 5*$signed(b) + 4*$signed(c) - $signed({1'b0,index}); 
                    c5_C <= -$signed(a) + $signed(c); 
                    c5_D <= $signed(b); 
                    c5_t <= $signed({1'b0,cur_W[19:0]}); h_row <= 2'd1; 
                    rom_addr <= rom_addr - 3 + length;
                end
                cubic2_5: begin
                    if (tmp[76]) f2 <= 8'd0;
                    else if (tmp > (75'sd255 << 61)) f2 <= 8'd255;
                    else f2 <= tmp[68:61];
                    rom_addr <= rom_addr + 1;
                    //cur_w <= (cur_W >> 8) - 1;
                    //cur_h <= (cur_H >> 8) + 1;
                end
                cubic3_1: begin
                    a <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic3_2: begin
                    b <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic3_3: begin
                    c <= $signed({1'b0, index});
                    //cur_w <= cur_w + 1;
                end
                cubic3_4: begin
                    //tmp <= ((((((-a) + 3*b - 3*c + $signed({1'b0, index})) * cur_W[19:0])) + ((2*a - 5*b + 4*c - $signed({1'b0, index})) << 20)) * cur_W[19:0] + (((-a) + c) << 40)) * cur_W[19:0] + (b << 61) + (80'sd1 << 60);
                    c5_A <= -$signed(a) + 3*$signed(b) - 3*$signed(c) + $signed({1'b0,index}); 
                    c5_B <= 2*$signed(a) - 5*$signed(b) + 4*$signed(c) - $signed({1'b0,index}); 
                    c5_C <= -$signed(a) + $signed(c); 
                    c5_D <= $signed(b); 
                    c5_t <= $signed({1'b0,cur_W[19:0]}); h_row <= 2'd2; 
                    rom_addr <= rom_addr - 3 + length;
                end
                cubic3_5: begin
                    if (tmp[76]) f3 <= 8'd0;
                    else if (tmp > (75'sd255 << 61)) f3 <= 8'd255;
                    else f3 <= tmp[68:61];
                    rom_addr <= rom_addr + 1;
                    // cur_w <= (cur_W >> 8) - 1;
                    // cur_h <= (cur_H >> 8);
                end
                cubic4_1: begin
                    a <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic4_2: begin
                    b <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                cubic4_3: begin
                    c <= $signed({1'b0, index});
                    //cur_w <= cur_w + 1;
                end
                cubic4_4: begin
                    //tmp <= ((((((-a) + 3*b - 3*c + $signed({1'b0, index})) * cur_W[19:0])) + ((2*a - 5*b + 4*c - $signed({1'b0, index})) << 20)) * cur_W[19:0] + (((-a) + c) << 40)) * cur_W[19:0] + (b << 61) + (80'sd1 << 60);
                    c5_A <= -$signed(a) + 3*$signed(b) - 3*$signed(c) + $signed({1'b0,index}); 
                    c5_B <= 2*$signed(a) - 5*$signed(b) + 4*$signed(c) - $signed({1'b0,index}); 
                    c5_C <= -$signed(a) + $signed(c); 
                    c5_D <= $signed(b); 
                    c5_t <= $signed({1'b0,cur_W[19:0]}); 
                    h_row <= 2'd3; 
                end
                cubic4_5: begin
                    if (tmp[76]) f4 <= 8'd0;
                    else if (tmp > (75'sd255 << 61)) f4 <= 8'd255;
                    else f4 <= tmp[68:61];
                end
                cubic5_1: begin
                    //tmp <= ((((((-f1) + 3*f2 - 3*f3 + f4) * cur_H[19:0])) + ((2*f1 - 5*f2 + 4*f3 - f4) << 20)) * cur_H[19:0] + (((-f1) + f3) << 40)) * cur_H[19:0] + (f2 << 61) + (80'sd1 << 60);
                    c5_A <= -$signed(f1) + 3 * $signed(f2) - 3 * $signed(f3) + $signed(f4);
                    c5_B <= 2 * $signed(f1) - 5 * $signed(f2) + 4 * $signed(f3) - $signed(f4);
                    c5_C <= -$signed(f1) + $signed(f3);
                    c5_D <= $signed(f2);
                    c5_t <= $signed({1'b0, cur_H[19:0]});
                end
                cubic5_mul1: begin
                    c5_p1 <= ($signed(c5_A) * $signed(c5_t)) + ($signed({{22{c5_B[11]}}, c5_B}) <<< 20);
                end
                cubic5_mul2: begin
                    c5_p2 <= ($signed(c5_p1) * $signed(c5_t)) + ($signed({{47{c5_C[8]}}, c5_C}) <<< 40);
                end
                cubic5_mul3: begin
                    c5_p3_H <= $signed(c5_p2[55:28]) * $signed({1'b0, c5_t[19:0]});
                    c5_p3_L <= $unsigned(c5_p2[27:0]) * $unsigned(c5_t[19:0]);
                end
                cubic5_mul3_add: begin
                    c5_p3 <= ($signed({{28{c5_p3_H[48]}}, c5_p3_H}) <<< 28) + $signed({29'd0, c5_p3_L});
                end
                cubic5_add3: begin
                    tmp <= $signed(c5_p3) + ($signed({{68{c5_D[8]}}, c5_D}) <<< 61) + (77'sd1 <<< 60);
                end
                cubic5_2: begin
                    if (tmp[76]) result <= 8'd0;
                    else if (tmp > (75'sd255 << 61)) result <= 8'd255;
                    else result <= tmp[68:61];
                    ram_addr <= (TH_count * TW) + TW_count;
                end
                coincide: begin
                    result <= $signed({1'b0, index});
                    ram_addr <= (TH_count * TW) + TW_count;
                end
                coincide_W_1: begin
                    f1 <= $signed({1'b0, index});
                    rom_addr <= rom_addr + length;
                    //cur_h <= cur_h + 1;
                end
                coincide_W_2: begin
                    f2 <= $signed({1'b0, index});
                    rom_addr <= rom_addr + length;
                    //cur_h <= cur_h + 1;
                end
                coincide_W_3: begin
                    f3 <= $signed({1'b0, index});
                // cur_h <= cur_h + 1;
                end
                coincide_W_4: begin
                    f4 <= $signed({1'b0, index});
                end
                coincide_H_1: begin
                    f1 <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                coincide_H_2: begin
                    f2 <= $signed({1'b0, index});
                    rom_addr <= rom_addr + 1;
                    //cur_w <= cur_w + 1;
                end
                coincide_H_3: begin
                    f3 <= $signed({1'b0, index});
                    //cur_w <= cur_w + 1;
                end
                coincide_H_4: begin
                    f4 <= $signed({1'b0, index});
                end
                coincide_H_5: begin
                    //tmp <= ((((((-f1) + 3*f2 - 3*f3 + f4) * cur_W[19:0])) + ((2*f1 - 5*f2 + 4*f3 - f4) << 20)) * cur_W[19:0] + (((-f1) + f3) << 40)) * cur_W[19:0] + (f2 << 61) + (80'sd1 << 60);
                    c5_A <= -$signed(f1) + 3 * $signed(f2) - 3 * $signed(f3) + $signed(f4);
                    c5_B <= 2 * $signed(f1) - 5 * $signed(f2) + 4 * $signed(f3) - $signed(f4);
                    c5_C <= -$signed(f1) + $signed(f3);
                    c5_D <= $signed(f2);
                    c5_t <= $signed({1'b0, cur_W[19:0]});
                end
                coincide_H_mul1: begin
                    c5_p1 <= ($signed(c5_A) * $signed(c5_t)) + ($signed({{22{c5_B[11]}}, c5_B}) <<< 20);
                end
                coincide_H_mul2: begin
                    c5_p2 <= ($signed(c5_p1) * $signed(c5_t)) + ($signed({{47{c5_C[8]}}, c5_C}) <<< 40);
                end
                coincide_H_mul3: begin
                    c5_p3_H <= $signed(c5_p2[55:28]) * $signed({1'b0, c5_t[19:0]});
                    c5_p3_L <= $unsigned(c5_p2[27:0]) * $unsigned(c5_t[19:0]);
                end
                coincide_H_mul3_add: begin
                    c5_p3 <= ($signed({{28{c5_p3_H[48]}}, c5_p3_H}) <<< 28) + $signed({29'd0, c5_p3_L});
                end
                coincide_H_add3: begin
                    tmp <= $signed(c5_p3) + ($signed({{68{c5_D[8]}}, c5_D}) <<< 61) + (77'sd1 <<< 60);
                end
                coincide_H_6: begin
                    if (tmp[76]) result <= 8'd0;
                    else if (tmp > (75'sd255 << 61)) result <= 8'd255;
                    else result <= tmp[68:61];
                    ram_addr <= (TH_count * TW) + TW_count;
                end
                write_sram: begin
                    sram_wen <= 0;
                end
                check: begin
                    sram_wen <= 1;
                    if (TW_count < TW - 1) begin
                        TW_count <= TW_count + 1;
                        cur_W <= cur_W + STW;
                    end
                    else if (TH_count < TH - 1) begin
                        TW_count <= 0;
                        TH_count <= TH_count + 1;
                        cur_W <= {21'd0, H0, 20'd0};
                        cur_H <= cur_H + STH;
                    end
                end
                done_state: begin
                    DONE <= 1;
                end
            endcase
        end
    end

    always @(*) begin
        case (state)
            init: begin
                next_state = div_w_wait;
            end
            div_w_wait: begin
                if (div_done)
                    next_state = div_h_wait;
                else
                    next_state = div_w_wait;
            end
            div_h_wait: begin
                if (div_done)
                    next_state = start;
                else
                    next_state = div_h_wait;
            end
            start: begin
                if (cur_W[19:0] == 0) begin
                    if (cur_H[19:0] == 0) begin
                        next_state = wait_rom;
                    end
                    else begin
                        next_state = wait_rom_plus;
                    end
                end
                else if (cur_H[19:0] == 0) begin
                    next_state = wait_rom;
                end
                else begin
                    next_state = wait_rom;
                end
            end
            wait_rom: begin
                if (cur_W[19:0] == 0) begin
                    if (cur_H[19:0] == 0) begin
                        next_state = coincide;
                    end
                    else begin
                        next_state = coincide_W_1;
                    end
                end
                else if (cur_H[19:0] == 0) begin
                    next_state = coincide_H_1;
                end
                else begin
                    next_state = cubic1_1;
                end
            end
            wait_rom_plus: begin
                next_state = coincide_W_1;
            end
            cubic1_1:  next_state = cubic1_2;
            cubic1_2:  next_state = cubic1_3;
            cubic1_3:  next_state = cubic1_4;
            cubic1_4: next_state = cubic_h_mul1;
            cubic_h_mul1: next_state = cubic_h_mul2;
            cubic_h_mul2: next_state = cubic_h_mul3;
            cubic_h_mul3: next_state = cubic_h_mul3_add;
            cubic_h_mul3_add: next_state = cubic_h_add3;
            cubic_h_add3: begin
                case (h_row)
                    2'd0: next_state = cubic1_5;
                    2'd1: next_state = cubic2_5;
                    2'd2: next_state = cubic3_5;
                    2'd3: next_state = cubic4_5;
                    default: next_state = cubic1_5;
                endcase
            end
            cubic1_5:  next_state = cubic2_1;
            cubic2_1:  next_state = cubic2_2;
            cubic2_2:  next_state = cubic2_3;
            cubic2_3:  next_state = cubic2_4;
            cubic2_4:  next_state = cubic_h_mul1;
            cubic2_5:  next_state = cubic3_1;
            cubic3_1:  next_state = cubic3_2;
            cubic3_2:  next_state = cubic3_3;
            cubic3_3:  next_state = cubic3_4;
            cubic3_4:  next_state = cubic_h_mul1;
            cubic3_5:  next_state = cubic4_1;
            cubic4_1:  next_state = cubic4_2;
            cubic4_2:  next_state = cubic4_3;
            cubic4_3:  next_state = cubic4_4;
            cubic4_4:  next_state = cubic_h_mul1;
            cubic4_5:  next_state = cubic5_1;
            cubic5_1:  next_state = cubic5_mul1;
            cubic5_mul1: next_state = cubic5_mul2;
            cubic5_mul2: next_state = cubic5_mul3;
            cubic5_mul3: next_state = cubic5_mul3_add;
            cubic5_mul3_add: next_state = cubic5_add3;
            cubic5_add3: next_state = cubic5_2;
            cubic5_2:  next_state = write_sram;
            coincide:  next_state = write_sram;
            coincide_W_1: next_state = coincide_W_2;
            coincide_W_2: next_state = coincide_W_3;
            coincide_W_3: next_state = coincide_W_4;
            coincide_W_4: next_state = cubic5_1;
            coincide_H_1: next_state = coincide_H_2;
            coincide_H_2: next_state = coincide_H_3;
            coincide_H_3: next_state = coincide_H_4;
            coincide_H_4: next_state = coincide_H_5;
            coincide_H_5:    next_state = coincide_H_mul1;
            coincide_H_mul1: next_state = coincide_H_mul2;
            coincide_H_mul2: next_state = coincide_H_mul3;
            coincide_H_mul3: next_state = coincide_H_mul3_add;
            coincide_H_mul3_add: next_state = coincide_H_add3;
            coincide_H_add3: next_state = coincide_H_6;
            coincide_H_6: next_state = write_sram;
            write_sram: next_state = check;
            check: begin
                    if (TW_count < TW - 1) begin
                        next_state = start;
                    end
                    else if (TH_count < TH - 1) begin
                        next_state = start;
                    end
                    else next_state = done_state;
            end
            done_state: begin
                next_state = done_state;
            end
            default:   next_state = init;
        endcase
    end

    endmodule

module divider_48_6 (
    input             clk,
    input             rst,
    input             start,
    input      [47:0] dividend,
    input      [5:0]  divisor,

    output reg        busy,
    output reg        done,
    output reg [47:0] quotient
);

    reg [47:0] dividend_reg;
    reg [48:0] remainder;
    reg [5:0]  divisor_reg;
    reg [5:0]  count;

    wire [48:0] remainder_shift;
    wire [48:0] divisor_ext;
    wire        ge;
    wire [48:0] remainder_next;
    wire [47:0] quotient_next;

    assign remainder_shift =
        {remainder[47:0], dividend_reg[47]};

    assign divisor_ext =
        {43'd0, divisor_reg};

    assign ge =
        (remainder_shift >= divisor_ext);

    assign remainder_next =
        ge ? (remainder_shift - divisor_ext)
           : remainder_shift;

    assign quotient_next =
        {quotient[46:0], ge};


    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dividend_reg <= 0;
            divisor_reg  <= 0;
            remainder    <= 0;
            quotient     <= 0;
            count        <= 0;
            busy         <= 0;
            done         <= 0;
        end
        else begin
            // done 只維持一個 clock
            done <= 1'b0;

            if (start && !busy) begin

                if (divisor == 0) begin
                    quotient <= 0;
                    busy     <= 0;
                    done     <= 1;
                end
                else begin
                    dividend_reg <= dividend;
                    divisor_reg  <= divisor;

                    remainder <= 0;
                    quotient  <= 0;

                    count <= 6'd48;
                    busy  <= 1'b1;
                end
            end

            else if (busy) begin

                remainder <= remainder_next;

                dividend_reg <= {
                    dividend_reg[46:0],
                    1'b0
                };

                quotient <= quotient_next;

                if (count == 1) begin
                    count <= 0;
                    busy  <= 0;
                    done  <= 1;
                end
                else begin
                    count <= count - 1'b1;
                end
            end
        end
    end

endmodule