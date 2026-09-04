//=============================================================================
// tb_id_ex.v — id_ex 单测（doc/modules/id_ex.md 验收，T30）
//   rst 清零；常规沿沿打入（逐字段）；bubble=1 全 0（气泡）；
//   气泡后恢复正常打入。
//=============================================================================
`timescale 1ns/1ps

module tb_id_ex;

    reg         clk = 0;
    reg         rst = 1;
    reg         bubble;
    reg  [31:0] pc, rs1_data, rs2_data, imm;
    reg  [4:0]  rd, rs1, rs2;
    reg  [3:0]  alu_op;
    reg  [1:0]  src_a, src_b;
    reg         mem_read, mem_write, mem_to_reg, reg_write;
    reg  [1:0]  jump;
    reg         bne;

    wire [31:0] idex_pc, idex_rs1_data, idex_rs2_data, idex_imm;
    wire [4:0]  idex_rd, idex_rs1, idex_rs2;
    wire [3:0]  idex_alu_op;
    wire [1:0]  idex_src_a, idex_src_b;
    wire        idex_mem_read, idex_mem_write, idex_mem_to_reg, idex_reg_write;
    wire [1:0]  idex_jump;
    wire        idex_bne;

    integer err = 0;
    integer n   = 0;

    id_ex dut (
        .clk            (clk),
        .rst            (rst),
        .bubble         (bubble),
        .pc             (pc),
        .rs1_data       (rs1_data),
        .rs2_data       (rs2_data),
        .imm            (imm),
        .rd             (rd),
        .rs1            (rs1),
        .rs2            (rs2),
        .alu_op         (alu_op),
        .src_a          (src_a),
        .src_b          (src_b),
        .mem_read       (mem_read),
        .mem_write      (mem_write),
        .mem_to_reg     (mem_to_reg),
        .reg_write      (reg_write),
        .jump           (jump),
        .bne            (bne),
        .idex_pc        (idex_pc),
        .idex_rs1_data  (idex_rs1_data),
        .idex_rs2_data  (idex_rs2_data),
        .idex_imm       (idex_imm),
        .idex_rd        (idex_rd),
        .idex_rs1       (idex_rs1),
        .idex_rs2       (idex_rs2),
        .idex_alu_op    (idex_alu_op),
        .idex_src_a     (idex_src_a),
        .idex_src_b     (idex_src_b),
        .idex_mem_read  (idex_mem_read),
        .idex_mem_write (idex_mem_write),
        .idex_mem_to_reg(idex_mem_to_reg),
        .idex_reg_write (idex_reg_write),
        .idex_jump      (idex_jump),
        .idex_bne       (idex_bne)
    );

    always #5 clk = ~clk;

    // 复位/气泡后全 0 检查
    task chk_all_zero;
        input [255:0] name;
        begin
            n = n + 1;
            if (idex_pc!==0 || idex_rs1_data!==0 || idex_rs2_data!==0 || idex_imm!==0 ||
                idex_rd!==0 || idex_rs1!==0 || idex_rs2!==0 || idex_alu_op!==0 ||
                idex_src_a!==0 || idex_src_b!==0 || idex_mem_read!==0 || idex_mem_write!==0 ||
                idex_mem_to_reg!==0 || idex_reg_write!==0 || idex_jump!==0 || idex_bne!==0) begin
                err = err + 1;
                $display("FAIL: %0d %0s not all zero", n, name);
            end else begin
                $display("PASS: %0d %0s all zero", n, name);
            end
        end
    endtask

    // 全字段等于输入检查
    task chk_latch;
        input [255:0] name;
        begin
            n = n + 1;
            if (idex_pc!==pc || idex_rs1_data!==rs1_data || idex_rs2_data!==rs2_data ||
                idex_imm!==imm || idex_rd!==rd || idex_rs1!==rs1 || idex_rs2!==rs2 ||
                idex_alu_op!==alu_op || idex_src_a!==src_a || idex_src_b!==src_b ||
                idex_mem_read!==mem_read || idex_mem_write!==mem_write ||
                idex_mem_to_reg!==mem_to_reg || idex_reg_write!==reg_write ||
                idex_jump!==jump || idex_bne!==bne) begin
                err = err + 1;
                $display("FAIL: %0d %0s latch mismatch", n, name);
            end else begin
                $display("PASS: %0d %0s latch ok", n, name);
            end
        end
    endtask

    initial begin
        bubble = 0;
        pc = 32'h0; rs1_data = 32'h0; rs2_data = 32'h0; imm = 32'h0;
        rd = 0; rs1 = 0; rs2 = 0; alu_op = 0; src_a = 0; src_b = 0;
        mem_read = 0; mem_write = 0; mem_to_reg = 0; reg_write = 0; jump = 0; bne = 0;

        // 复位清零（异步）
        #2 chk_all_zero("reset");
        rst = 0;
        // 沿沿打入
        pc = 32'h0000001C; rs1_data = 32'h11111111; rs2_data = 32'h22222222;
        imm = 32'hFFFFFFF0; rd = 5'd10; rs1 = 5'd11; rs2 = 5'd12;
        alu_op = 4'b1001; src_a = 2'b10; src_b = 2'b01;
        mem_read = 1; mem_write = 0; mem_to_reg = 1; reg_write = 1; jump = 2'b00; bne = 0;
        @(posedge clk);
        #1 chk_latch("latch-1");
        // 第二次打入不同值
        rd = 5'd3; rs1 = 5'd4; rs2 = 5'd5; alu_op = 4'b0001; src_a = 0; src_b = 2'b10;
        mem_read = 0; mem_write = 1; mem_to_reg = 0; reg_write = 0; jump = 2'b10; bne = 1;
        imm = 32'h00000008;
        @(posedge clk);
        #1 chk_latch("latch-2");
        // bubble=1：全 0（即使输入非 0）
        bubble = 1;
        pc = 32'hDEADBEEF; rs1_data = 32'h1; rs2_data = 32'h2; imm = 32'h3;
        rd = 5'd7; rs1 = 5'd8; rs2 = 5'd9; alu_op = 4'hF; src_a = 2'b11; src_b = 2'b11;
        mem_read = 1; mem_write = 1; mem_to_reg = 1; reg_write = 1; jump = 2'b11; bne = 1;
        @(posedge clk);
        #1 chk_all_zero("bubble");
        // bubble=0 恢复打入
        bubble = 0;
        pc = 32'h00000020; rs1_data = 32'hA; rs2_data = 32'hB; imm = 32'hC;
        rd = 5'd1; rs1 = 5'd2; rs2 = 5'd3; alu_op = 4'b0010; src_a = 2'b00; src_b = 2'b01;
        mem_read = 0; mem_write = 0; mem_to_reg = 0; reg_write = 1; jump = 2'b00; bne = 0;
        @(posedge clk);
        #1 chk_latch("latch-after-bubble");

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
