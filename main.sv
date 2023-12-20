`define TARGET_CLOCK_PERIOD 10

interface therm_n1_register;
    logic   [63:0]  value [31:0];
    logic   [63:0]  program_counter;
endinterface

interface therm_simple_memory (
    input   bit     clock
);
    logic   [31:0]  data_store;
    logic   [31:0]  data_load;
    logic   [63:0]  address;

    bit     write_enable;
    bit     chip_enable;
endinterface

typedef logic [31:0] word;

module therm_n1_decode_i_type
(
    input   logic       reset_neg,
    therm_n1_register   register,
    input   word        instruction,

    inout   logic   [63:0]       rd,
    inout   logic   [63:0]       rs1,
    inout   integer imm
);
    //wtf
    assign rd           = reset_neg ? register.value[ instruction[11:7] ] : 64'bZ;
    assign rs1          = reset_neg ? register.value[ instruction[19:15] ] : 64'bZ;
    assign imm[11:0]    = reset_neg ? instruction[31:20] : 12'bZ;

    specify
        clock *> rd  = TARGET_CLOCK_PERIOD;
        clock *> rs1 = TARGET_CLOCK_PERIOD;
    endspecify

endmodule

module therm_n1_decode(
    input   bit         clock,
    input   word        instruction,
    therm_n1_register   register,
    inout   logic       reset_neg
);

    logic   i_type_en = 0;

    integer imm;
    logic   [63:0]   rd;
    logic   [63:0]   rs1;
    logic   [63:0]   rs2;

    therm_n1_decode_i_type i_type (
        .reset_neg  (reset_neg ? i_type_en : 0),
        .register (register),
        .instruction(instruction),
        .rd         (rd),
        .rs1        (rs1),
        .imm        (imm)
    );

    always @(*) begin
        if(instruction[1:0] != 2'b11) begin
            reset_neg = 0;
            $display ("Ill-formed instruction or not supported: %h",instruction);
            $finish;
        end

        /* verilator lint_off CASEINCOMPLETE */

        case(instruction[6:2])
            5'b00_000: begin    //LOAD
                i_type_en  = 1;
            end
        endcase
    end


endmodule

module therm_n1_fetch
(
    input   bit                 clock,
    inout   logic               reset_neg,
    therm_n1_register           register,
    therm_simple_memory         memory,
    output  word                instruction
);
    logic wait_for_read = 0;

    always @(posedge clock) begin
        register.program_counter    <= register.program_counter + 1;
        memory.address              <= register.program_counter;
        memory.chip_enable          <= 1;
        wait_for_read               <= 1;
    end

    always @(negedge memory.clock) begin
        if( wait_for_read ) begin
            instruction             <= memory.data_load;
            memory.chip_enable      <= 0;
        end
    end

    specify
        clock *> instruction = TARGET_CLOCK_PERIOD;
        $hold(clock, memory.data_load, TARGET_CLOCK_PERIOD * 0.2);
    endspecify

endmodule



module therm_n1 (
    input   bit     primary_clock,
    inout   logic   reset_neg
);
    integer tick_tock;

    logic   fetch_tick = tick_tock == 0'd0 ? 1 : 0;
    logic   decode_tick = tick_tock == 0'd1 ? 1 : 0;

    always @(posedge primary_clock or negedge reset_neg) begin
        if(reset_neg)
        tick_tock <= tick_tock + 1;
    end

    therm_n1_register register ();
    assign register.value[0] = 0;

    therm_simple_memory memory ( primary_clock );

    word instruction;

    therm_n1_fetch fetch(
        .clock (fetch_tick),
        .reset_neg (reset_neg),
        .register (register),
        .memory (memory),
        .instruction (instruction)
    );
    therm_n1_decode decode (
        .clock (decode_tick),
        .reset_neg (reset_neg),
        .instruction (instruction),
        .register (register)
    );
endmodule
