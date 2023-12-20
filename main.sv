`define TARGET_CLOCK_PERIOD 10

interface therm_n1_register;
    logic   [63:0]  value [31:0];
    logic   [63:0]  program_counter;
endinterface

interface therm_simple_memory (
    input   bit     clock
);
    logic   [63:0]  data_store;
    logic   [63:0]  data_load;
    logic   [63:0]  address;

    bit     write_enable;
    bit     chip_enable;
endinterface

typedef logic [31:0] word;

module signed_extensior
#(
    parameter   sign_bit = 63
)
(
    input   logic   [sign_bit:0]    in_num,
    output  logic   [63:0]    out_num
);
    assign  out_num = {{(63 - sign_bit){in_num[sign_bit]}}, in_num};
endmodule

module therm_n1_decode(
    input   bit         clock,
    input   word        instruction,
    therm_n1_register   register,
    therm_simple_memory memory,
    inout   logic       reset_neg
);
    logic   [63:0]   rd;
    logic   [63:0]   rs1;
    logic   [63:0]   rs2;
    logic   [63:0]   imm20;

    assign rs1 = register.value[instruction[19:15]];
    assign rs2 = register.value[instruction[24:20]];
    assign rd  = register.value[instruction[11:7]];
    
    signed_extensior  #(.sign_bit(19)) extensior_imm20 (
        .in_num(instruction[31:12]),
        .out_num(imm20)
    );

    logic   [63:0]  signed_extensior_number;

    logic   [63:0]  signed_extensior_out;
    logic   [63:0]  signed_extensior_outb;
    logic   [63:0]  signed_extensior_outh;
    logic   [63:0]  signed_extensior_outw;
    logic   [63:0]  signed_extensior_outd;

    logic   [1:0]   signed_extensior_sel;
    assign  signed_extensior_out = 
    signed_extensior_sel == 2'b00 ? signed_extensior_outb :
    signed_extensior_sel == 2'b01 ? signed_extensior_outh :
    signed_extensior_sel == 2'b10 ? signed_extensior_outw :
                                    signed_extensior_outd;

    signed_extensior  #(.sign_bit(7)) extensior_byte (
        .in_num(signed_extensior_number[7:0]),
        .out_num(signed_extensior_outb)
    );
    signed_extensior  #(.sign_bit(15)) extensior_half (
        .in_num(signed_extensior_number[15:0]),
        .out_num(signed_extensior_outb)
    );

    signed_extensior  #(.sign_bit(31)) extensior_word (
        .in_num(signed_extensior_number[31:0]),
        .out_num(signed_extensior_outb)
    );

    signed_extensior  #(.sign_bit(63)) extensior_dword (
        .in_num(signed_extensior_number),
        .out_num(signed_extensior_outb)
    );

    

    always @(posedge clock) begin
        if(instruction[1:0] != 2'b11) begin
            reset_neg <= 0;
            $display ("Ill-formed instruction or not supported: %h",instruction);
            $finish;
        end
        /* verilator lint_off CASEINCOMPLETE */
        case(instruction[6:2])
            5'b00_000: begin    //LOAD

            memory.address      <= rs1 + imm20;
            memory.write_enable <= 0;
            memory.chip_enable  <= 1;
            
            end
        endcase
    end
    
    always @(negedge memory.clock) begin
        /* verilator lint_off CASEINCOMPLETE */
        case(instruction[6:2])
            5'b00_000: begin    //LOAD
            signed_extensior_number <= memory.data_load;
            memory.chip_enable      <= 0;
            signed_extensior_sel    <= instruction[15:14];
            rd                      <= instruction[16] ? signed_extensior_number : signed_extensior_out;
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
            instruction             <= memory.data_load[31:0];
            memory.chip_enable      <= 0;
        end
    end
endmodule



module therm_n1 (
    input   bit     primary_clock,
    inout   logic   reset_neg
);
    integer tick_tock;

    logic   fetch_tick = tick_tock == 0'd0 ? 1 : 0;
    logic   decode_tick = tick_tock == 0'd1 ? 1 : 0;

    always @(posedge primary_clock) begin
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
        .memory (memory),
        .register (register)
    );
endmodule
