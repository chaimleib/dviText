module vram (
    input              clk,
    input       [18:0] ra,
    output reg  [31:0] rd,

    input       [18:0] wa,
    input       [31:0] wd,
    input              we);
    
    reg [31:0] ram [2^19-1:0];

    always @(posedge clk) begin
        rd <= ram[ra];

        if (we) ram[wa] <= wd;
    end

endmodule
