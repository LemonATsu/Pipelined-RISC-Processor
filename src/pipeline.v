module pipeline(
  input  clk, rst_n,
  `ifdef N_MEM_TEST
  input  [31:0] IF,
  `endif
  input  [31:0] D_OUT, // out from memory
  output [31:0] D_IN,  // go into memory
  output [31:0] M_ADDR // memory access.
);


wire [31:0] BrA, RAA;
reg  [31:0] MUX_C, PC_NEXT;
reg  [31:0] PC, PC_1, PC_2;      // Per stage PC, maintain the PC of the stage.
wire [1:0]  C_SELECT;


reg  [31:0] IR;                  // for ID, came from IF.
reg  HA, HB;                     // for ID, came out from fwd unit.
wire MA, MB;                     // for ID, came out from ins decoder.
wire CS;                         // for ID, came out from ins decoder.
wire ID_RW, ID_PS, ID_MW;        // for ID, came out from ins decoder.
wire [1:0]  ID_MD, ID_BS;        // for ID, came out from ins decoder
wire [3:0]  ID_FS;               // for ID, came out from ins decoder
wire [4:0]  ID_DA, ID_AA, ID_BA; // for ID, came out from ins decoder.
wire [31:0] RA, RB;              // for ID, came out from reg file.
reg  [31:0] BUS_A, BUS_B;        // for ID, came out from reg A/B.
reg  [31:0] FWD;                 // for ID, came out from fwd unit.
reg  [31:0] IM;                  // for ID, came out from constant unit.
reg  [4:0]  ID_SH;               // for ID, came out from IR directly.

wire V, C, N, Z;                 // for EX, came out from func unit.
wire [31:0]   F;                 // for EX, came out from func unit.
reg  [31:0] EX_BUSA, EX_BUSB;        // for EX, came from ID stage.
reg  EX_RW, EX_PS, EX_MW;        // for EX, came from ID stage.
reg  [1:0]  EX_MD, EX_BS;        // for EX, came from ID stage.
reg  [4:0]  EX_DA, EX_AA, EX_BA; // for EX, came from ID stage. Note that AA, BA may not be used. It's for modified to 5 stage.
reg  [3:0]  EX_FS;               // for EX, came from ID stage.
reg  [4:0]  EX_SH;               // for EX, came from ID stage.


reg WB_RW;
reg [1:0]  WB_MD;
reg [4:0]  WB_DA;
reg [31:0] WB_F, WB_SLT, WB_DOUT;
reg [31:0] BUS_D;          


/* Stage manager */
  // handle per stage pc.
  always @(posedge clk) begin
    if(!rst_n) begin
      {PC, PC_1, PC_2} = 0;
    end else begin
      PC_2  = PC_1;
      PC_1  = PC;
      PC    = PC_NEXT;
    end
  end

  always @(*) begin
    PC_NEXT = PC + 1;
    case(C_SELECT)
      2'b01 : PC_NEXT = BrA;
      2'b10 : PC_NEXT = RAA;
      2'b11 : PC_NEXT = BrA;
    endcase
  end

  // handle shift amount between ID and EX.
  always @(posedge clk) begin
    if(!rst_n) begin
      {ID_SH, IM} = 0;
    end else begin
      EX_SH = ID_SH;
      ID_SH = IR[4:0];
    end
  end

  // Handle things that will pass to next stage.
  always @(posedge clk) begin
      if(!rst_n) begin
        {WB_RW, WB_MD, WB_DA, WB_F, WB_SLT, WB_DOUT}      = 0;
        {EX_FS, EX_RW, EX_DA, EX_MD, EX_BS, EX_PS, EX_FS} = 0;
      end else begin
        WB_RW   = EX_RW;
        WB_MD   = EX_MD;
        WB_DA   = EX_DA;
        WB_F    = F;
        WB_SLT  = {31'b0, N ^ Z};
        WB_DOUT = D_OUT;
        
        EX_RW   = ID_RW;
        EX_DA   = ID_DA;
        EX_AA   = ID_AA; // for modified to 5 stage.
        EX_BA   = ID_BA; // for modified to 5 stage.
        EX_MD   = ID_MD;
        EX_BS   = ID_BS;
        EX_PS   = ID_PS;
        EX_MW   = ID_MW;
        EX_FS   = ID_FS;
        EX_BUSA = BUS_A;
        EX_BUSB = BUS_B;
        IR      = IF;
      end
  end

/* stage : IF */

// step 1. retreive IR from instruction memory.
// step 2. if branch happen, make it become nop.



/* stage : ID */
// Since all the input to REGFILE is block by clock,
// We don't need to have a clock port.
// WB_DA only change when clock raise.
// WB_RW only change when clock raise.
// WB_DOUT, WB_F, WB_SLT only change when clock raise => BUS_D only change when clock raise.
// So basically, all port about register write only change when clock raise. 
register_file       REGF (.rst_n(rst_n), .RW(WB_RW),
                          .DA(WB_DA), .AA(ID_AA)   , .BA(ID_BA), .BUS_D(BUS_D),
                          .REG_A(RA), .REG_B(RB));

instruction_decoder INSDE(.IR(IR)   , .DA(ID_DA), .AA(ID_AA), .BA(ID_BA),
                          .RW(ID_RW), .MD(ID_MD), .BS(ID_BS), .PS(ID_PS), 
                          .MW(ID_MW), .FS(ID_FS), .MB(MB)   , .MA(MA)   , .CS(CS));
  // constant unit
  always @(*) begin
    IM = {17'h0_0000 ,IR[14:0]};
    // IF CS is true, and the leftmost of imm is 1,
    // it need to be extend.
    if(CS & IR[14]) begin
      IM = {17'h1_ffff, IR[14:0]};
    end
  end
  
  // mux A
  always @(*) begin
    BUS_A = RA;
    case({HA, MA})
      2'b00 : BUS_A = RA;
      2'b01 : BUS_A = PC_1; // for JML
      3'b10 : BUS_A = FWD;
    endcase
  end

  // mux B
  always @(*) begin
    BUS_B = RB;
    case({HB, MB})
      2'b00 : BUS_B = RB;
      2'b01 : BUS_B = IM; // for constant.
      3'b10 : BUS_B = FWD;
    endcase
  end


/* stage : EX */
func_unit FUNCUNIT(.FS(EX_FS), .SH(EX_SH), .A(EX_BUSA), .B(EX_BUSB), 
                    .V(V), .C(C), .N(N), .Z(Z), .F(F));



  // hazard detect unit 
  always @(*) begin
    // if EX_RW == 0, then data hazard won't happend.
    // if |EX_DA == 0, then data hazard won't happend because R0 need to be 0 all the time.
    // if MA/MB = 1, if means that it don't need REG A/B
    // finally, DA need to be equal to rather AA or BA.
    HA = (EX_RW) & (|EX_DA) & ~(MA) & (EX_DA == ID_AA);
    HB = (EX_RW) & (|EX_DA) & ~(MB) & (EX_DA == ID_BA);
  end

  // MUX D' (fwd unit)
  always @(*) begin
    FWD = 0;
    case(EX_MD)
      2'b00 : FWD = F;
      2'b01 : FWD = D_OUT;
      2'b10 : FWD = {31'b0, N ^ Z};
    endcase
  end

/* stage : WB */

  // MUX D
  always @(*) begin
    BUS_D = 0;
    case(WB_MD)
      2'b00 : BUS_D = WB_F;
      2'b01 : BUS_D = WB_DOUT;
      2'b10 : BUS_D = WB_SLT;
    endcase
  end


endmodule
