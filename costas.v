`timescale 1ns/10ps

module costas (clk, reset, pushADC, ADC, pushByte, Byte, Sync, lastByte, stopIn);
`include "tables.v"

  input clk,reset;
  input pushADC;
  input [9:0] ADC; // 10-bit, representing 2's complement -1~+1
  output pushByte;
  output [7:0] Byte;
  output Sync,lastByte;
  input stopIn;

  reg [9:0] ADC_0;
   // Pipeline for pushADC signal
  reg push_0, push_1, push_2, push_3, push_4, push_5, push_6, push_7, push_8;
  reg push_9, push_10, push_11;

  integer filt_cos[0:42], filt_sin[0:42], filt_cos_out, filt_sin_out;
  integer filt_cos_mul[0:42], filt_sin_mul[0:42], filt_cos_sum, filt_sin_sum;
  integer mul_2;
  integer mul_2_out, mul_2_out_d;

  reg [31:0] nco, nco_d;
  reg [31:0] phase, phase_d;
  reg [15:0] cos_from_table, msin_from_table;

  integer shift_reg[0:499];
  integer gp_1 [0:99];
  integer gp_2 [0:19];
  integer gp_3 [0:3];
  integer gp_4;
  reg     sync_sig;


  /*FILTER COEFFICIENTS*/
  function integer filt_coef(input integer index); // Scale up to 1024
    case (index)
      0:  filt_coef=2;
      1:  filt_coef=4;
      2:  filt_coef=4;
      3:  filt_coef=2;
      4:  filt_coef=-3;
      5:  filt_coef=-10;
      6:  filt_coef=-14;
      7:  filt_coef=-14;
      8:  filt_coef=-6;
      9:  filt_coef=7;
      10: filt_coef=19;
      11: filt_coef=22;
      12: filt_coef=12;
      13: filt_coef=-11;
      14: filt_coef=-36;
      15: filt_coef=-48;
      16: filt_coef=-35;
      17: filt_coef=11;
      18: filt_coef=83;
      19: filt_coef=161;
      20: filt_coef=221;
      21: filt_coef=244;
      22: filt_coef=221;
      23: filt_coef=161;
      24: filt_coef=83;
      25: filt_coef=11;
      26: filt_coef=-35;
      27: filt_coef=-48;
      28: filt_coef=-36;
      29: filt_coef=-11;
      30: filt_coef=12;
      31: filt_coef=22;
      32: filt_coef=19;
      33: filt_coef=7;
      34: filt_coef=-6;
      35: filt_coef=-14;
      36: filt_coef=-14;
      37: filt_coef=-10;
      38: filt_coef=-3;
      39: filt_coef=2;
      40: filt_coef=4;
      41: filt_coef=4;
      42: filt_coef=2;
      default:
          filt_coef=512;
    endcase // index
  endfunction
  /*FILTER COEFFICIENTS*/

  always @(negedge clk or posedge reset) begin
    if(reset) begin
      cos_from_table  <= #1 0;
      msin_from_table <= #1 0;
    end else begin
      if (push_0)
        {msin_from_table, cos_from_table} <= #1 scTable(nco[31:22]);
    end
  end

  function integer mul_1(input integer a, input integer b);
    mul_1 = a*b/512; // ADC is 10-bit -1~+1 (1 sign bit and 9 fractions)
  endfunction
  always @(negedge clk or posedge reset) begin
    if(reset) begin
      filt_cos[0] <= #1 0;
      filt_sin[0] <= #1 0;
    end else begin
      if (push_1) begin
        // 10-bit from ADC * 16-bit from sin/cos table
        filt_cos[0] <= #1 mul_1({{22{ADC_0[9]}},ADC_0}, {{16{cos_from_table[15]}}, cos_from_table});
        filt_sin[0] <= #1 mul_1({{22{ADC_0[9]}},ADC_0}, {{16{msin_from_table[15]}},msin_from_table});
      end
    end
  end

/*Filters*/
  genvar x;
  generate
    for (x=1; x<43; x=x+1) begin
      always @(negedge clk or posedge reset) begin
        if(reset) begin
          filt_cos[x] <= #1 0;
          filt_sin[x] <= #1 0;
        end else begin
          if (push_2) begin
            filt_cos[x] <= #1 filt_cos[x-1];
            filt_sin[x] <= #1 filt_sin[x-1];
          end
        end
      end
    end
  endgenerate

  integer x2, x3;
  always @(negedge clk or posedge reset) begin
    if(reset) begin
      for (x2=0; x2<43; x2=x2+1) begin
        filt_cos_mul[x2] <= #1 0;
        filt_sin_mul[x2] <= #1 0;
      end
    end else begin
      if (push_3) begin
        for (x3=0; x3<43; x3=x3+1) begin
          filt_cos_mul[x3] <= #1 (filt_coef(x3) * filt_cos[x3])/1024; // the Coefficient is scaled up to 1024
          filt_sin_mul[x3] <= #1 (filt_coef(x3) * filt_sin[x3])/1024;
        end
      end
    end
  end

  always @(negedge clk or posedge reset) begin
    if(reset) begin
      filt_cos_sum <= #1 0;
      filt_sin_sum <= #1 0;
    end else begin
      if (push_4) begin
          filt_cos_sum <= #1 filt_cos_mul[0]+  filt_cos_mul[1]+  filt_cos_mul[2]+
          filt_cos_mul[3]+   filt_cos_mul[4]+  filt_cos_mul[5]+  filt_cos_mul[6]+
          filt_cos_mul[7]+   filt_cos_mul[8]+  filt_cos_mul[9]+  filt_cos_mul[10]+
          filt_cos_mul[11]+  filt_cos_mul[12]+ filt_cos_mul[13]+ filt_cos_mul[14]+
          filt_cos_mul[15]+  filt_cos_mul[16]+ filt_cos_mul[17]+ filt_cos_mul[18]+
          filt_cos_mul[19]+  filt_cos_mul[20]+ filt_cos_mul[21]+ filt_cos_mul[22]+
          filt_cos_mul[23]+  filt_cos_mul[24]+ filt_cos_mul[25]+ filt_cos_mul[26]+
          filt_cos_mul[27]+  filt_cos_mul[28]+ filt_cos_mul[29]+ filt_cos_mul[30]+
          filt_cos_mul[31]+  filt_cos_mul[32]+ filt_cos_mul[33]+ filt_cos_mul[34]+
          filt_cos_mul[35]+  filt_cos_mul[36]+ filt_cos_mul[37]+ filt_cos_mul[38]+
          filt_cos_mul[39]+  filt_cos_mul[40]+ filt_cos_mul[41]+ filt_cos_mul[42];

          filt_sin_sum <= #1 filt_sin_mul[0]+  filt_sin_mul[1]+  filt_sin_mul[2]+
          filt_sin_mul[3]+   filt_sin_mul[4]+  filt_sin_mul[5]+  filt_sin_mul[6]+
          filt_sin_mul[7]+   filt_sin_mul[8]+  filt_sin_mul[9]+  filt_sin_mul[10]+
          filt_sin_mul[11]+  filt_sin_mul[12]+ filt_sin_mul[13]+ filt_sin_mul[14]+
          filt_sin_mul[15]+  filt_sin_mul[16]+ filt_sin_mul[17]+ filt_sin_mul[18]+
          filt_sin_mul[19]+  filt_sin_mul[20]+ filt_sin_mul[21]+ filt_sin_mul[22]+
          filt_sin_mul[23]+  filt_sin_mul[24]+ filt_sin_mul[25]+ filt_sin_mul[26]+
          filt_sin_mul[27]+  filt_sin_mul[28]+ filt_sin_mul[29]+ filt_sin_mul[30]+
          filt_sin_mul[31]+  filt_sin_mul[32]+ filt_sin_mul[33]+ filt_sin_mul[34]+
          filt_sin_mul[35]+  filt_sin_mul[36]+ filt_sin_mul[37]+ filt_sin_mul[38]+
          filt_sin_mul[39]+  filt_sin_mul[40]+ filt_sin_mul[41]+ filt_sin_mul[42];
      end
    end
  end
/*Filters*/

  always @(negedge clk or posedge reset) begin
    if (reset) begin
      filt_cos_out <= #1 0;
      filt_sin_out <= #1 0;
    end
    else begin
      if (push_5) begin
        filt_cos_out <= #1 filt_cos_sum;
        filt_sin_out <= #1 filt_sin_sum;
      end
    end
  end

  always @(*) begin
    mul_2       = filt_cos_out*filt_sin_out;
    mul_2_out_d = {{16{mul_2[31]}}, mul_2[31:16]}; // 16-bit Sin wave
  end

  always @(negedge clk or posedge reset) begin
    if(reset) begin
      mul_2_out <= #1 0;
    end else begin
      if (push_6) begin
        mul_2_out <= #1 mul_2_out_d;
        end
    end
  end

  always @(*) begin
    nco_d = nco;
    phase_d = phase;
    if (push_0) begin
      nco_d = nco+phase;
    end
    if (push_7) begin
      phase_d = 32'd429496729 + (mul_2_out<<14); // 2^32/10 & move up to meet 16 bit requirement

    end
  end

  integer y, z, ig1_1, ig1_2, ig2, ig3;
  always @(negedge clk or posedge reset) begin
    if(reset) begin
      for (y=0; y<500; y=y+1) begin
        shift_reg[y] <= #1 0;
      end
    end else begin
      if (push_6) begin
        shift_reg[0] <= #1 filt_cos_out;
        for(y=1; y<500; y=y+1) begin
          shift_reg[y] <= #1 shift_reg[y-1];
        end
      end
    end
  end

  always @(negedge clk or posedge reset) begin
    if(reset) begin
      for (z=0; z<100; z=z+1) begin
        gp_1[z] <= #1 0;
      end
    end else begin
      for (ig1_1=0; ig1_1<20; ig1_1=ig1_1+1) begin
        for (ig1_2=0; ig1_2<5; ig1_2=ig1_2+1) begin
          if (push_7) begin
            gp_1[ig1_1*5+ig1_2] <= #1 shift_reg[ig1_1*25+ig1_2*5+0]+
                                      shift_reg[ig1_1*25+ig1_2*5+1]+
                                      shift_reg[ig1_1*25+ig1_2*5+2]+
                                      shift_reg[ig1_1*25+ig1_2*5+3]+
                                      shift_reg[ig1_1*25+ig1_2*5+4];
          end
        end
      end
    end
  end
  
  //  1001111100   0110000011:  The start sync signal
  always @(negedge clk or posedge reset) begin
    if(reset) begin
      for (ig2=0; ig2<20; ig2=ig2+1) begin
        gp_2[ig2] <= #1 0;
      end
    end else begin
      if (push_8) begin
        gp_2[0]  <= #1   gp_1[0] +gp_1[1] +gp_1[2] +gp_1[3] +gp_1[4]; // 5*5=25 samples
        gp_2[1]  <= #1   gp_1[5] +gp_1[6] +gp_1[7] +gp_1[8] +gp_1[9];
        gp_2[2]  <= #1 ~(gp_1[10]+gp_1[11]+gp_1[12]+gp_1[13]+gp_1[14]) + 32'd1;
        gp_2[3]  <= #1 ~(gp_1[15]+gp_1[16]+gp_1[17]+gp_1[18]+gp_1[19]) + 32'd1;
        gp_2[4]  <= #1 ~(gp_1[20]+gp_1[21]+gp_1[22]+gp_1[23]+gp_1[24]) + 32'd1;
        gp_2[5]  <= #1 ~(gp_1[25]+gp_1[26]+gp_1[27]+gp_1[28]+gp_1[29]) + 32'd1;
        gp_2[6]  <= #1 ~(gp_1[30]+gp_1[31]+gp_1[32]+gp_1[33]+gp_1[34]) + 32'd1;
        gp_2[7]  <= #1   gp_1[35]+gp_1[36]+gp_1[37]+gp_1[38]+gp_1[39];
        gp_2[8]  <= #1   gp_1[40]+gp_1[41]+gp_1[42]+gp_1[43]+gp_1[44];
        gp_2[9]  <= #1 ~(gp_1[45]+gp_1[46]+gp_1[47]+gp_1[48]+gp_1[49]) + 32'd1;
        gp_2[10] <= #1 ~(gp_1[50]+gp_1[51]+gp_1[52]+gp_1[53]+gp_1[54]) + 32'd1;
        gp_2[11] <= #1 ~(gp_1[55]+gp_1[56]+gp_1[57]+gp_1[58]+gp_1[59]) + 32'd1;
        gp_2[12] <= #1   gp_1[60]+gp_1[61]+gp_1[62]+gp_1[63]+gp_1[64];
        gp_2[13] <= #1   gp_1[65]+gp_1[66]+gp_1[67]+gp_1[68]+gp_1[69];
        gp_2[14] <= #1   gp_1[70]+gp_1[71]+gp_1[72]+gp_1[73]+gp_1[74];
        gp_2[15] <= #1   gp_1[75]+gp_1[76]+gp_1[77]+gp_1[78]+gp_1[79];
        gp_2[16] <= #1   gp_1[80]+gp_1[81]+gp_1[82]+gp_1[83]+gp_1[84];
        gp_2[17] <= #1 ~(gp_1[85]+gp_1[86]+gp_1[87]+gp_1[88]+gp_1[89]) + 32'd1;
        gp_2[18] <= #1 ~(gp_1[90]+gp_1[91]+gp_1[92]+gp_1[93]+gp_1[94]) + 32'd1;
        gp_2[19] <= #1   gp_1[95]+gp_1[96]+gp_1[97]+gp_1[98]+gp_1[99];
      end
    end
  end

  always @(negedge clk or posedge reset) begin
    if(reset) begin
      for (ig3=0; ig3<4; ig3=ig3+1) begin
        gp_3[ig3] <= #1 0;
      end
    end else begin
      if (push_9) begin
        gp_3[0] <= #1 gp_2[0] +gp_2[1] +gp_2[2] +gp_2[3] +gp_2[4];
        gp_3[1] <= #1 gp_2[5] +gp_2[6] +gp_2[7] +gp_2[8] +gp_2[9];
        gp_3[2] <= #1 gp_2[10]+gp_2[11]+gp_2[12]+gp_2[13]+gp_2[14];
        gp_3[3] <= #1 gp_2[15]+gp_2[16]+gp_2[17]+gp_2[18]+gp_2[19];
      end
    end
  end

  always @(negedge clk or posedge reset) begin
    if(reset) begin
      gp_4 <= #1 0;
    end else begin
      if (push_10) begin
        gp_4 <= #1 gp_3[0]+gp_3[1]+gp_3[2]+gp_3[3];
      end
    end
  end


/*State machine for decoding*/
  reg         [2:0] state, next_state;
  reg signed [31:0] sync_sr [0:249];
  reg         [9:0] dec_in, dec_in_d;
  reg         [1:0] st_push, st_push_d; // State for push out
  reg               pushB, pushB_d;
  reg         [7:0] Bout, Bout_d;
  reg         [7:0] Boutp, Boutp_d;
  reg               lastB, lastB_d;
  reg               Syncout, Syncout_d;
  integer           cnt, cnt_d;
  integer           Bcnt, Bcnt_d;

  integer maxSyncSig, maxSyncSig_d;
  always @(*) begin
    maxSyncSig_d = maxSyncSig;
  end  
  always @ (negedge clk or posedge reset) begin
    if (reset) begin
      sync_sig   <= #1 0;
      maxSyncSig <= #1 32'd4900000;
    end else begin
      if (push_11 && (cnt==0)) begin
        // ~500*(+/-10000) each output
/*
        if ({gp_4[31], maxSyncSig[31]} == 2'b00) begin
            if (gp_4 >= maxSyncSig) begin
              sync_sig   <= #1 1;
              maxSyncSig <= #1 gp_4;  
            end else begin
              sync_sig   <= #1 0;
              maxSyncSig <= #1 maxSyncSig_d;  
            end
        end
        else if ({gp_4[31], maxSyncSig[31]} == 2'b01) begin
            if (gp_4 >= (-maxSyncSig)) begin
              sync_sig   <= #1 1;
              maxSyncSig <= #1 gp_4;  
            end else begin
              sync_sig   <= #1 0;
              maxSyncSig <= #1 maxSyncSig_d;  
            end
        end
        else if ({gp_4[31], maxSyncSig[31]} == 2'b10) begin
            if ((-gp_4) >= maxSyncSig) begin
              sync_sig   <= #1 1;
              maxSyncSig <= #1 gp_4;  
            end else begin
              sync_sig   <= #1 0;
              maxSyncSig <= #1 maxSyncSig_d;  
            end
        end
        else if ({gp_4[31], maxSyncSig[31]} == 2'b11) begin
            if (gp_4 <= maxSyncSig) begin
              sync_sig   <= #1 1;
              maxSyncSig <= #1 gp_4;  
            end else begin
              sync_sig   <= #1 0;
              maxSyncSig <= #1 maxSyncSig_d;  
            end
        end
      else begin
        sync_sig   <= #1 0;
        maxSyncSig <= #1 maxSyncSig_d;
      end
*/

//        if ((gp_4>=5050000) || (gp_4<=(-5050000))) begin
        if ((gp_4>=4950000) || (gp_4<=(-4950000))) begin
          sync_sig   <= #1 1;
        end else begin
          sync_sig <= #1 0;
        end
      
      end
    end
  end
  
  // 5/6 Encode
  function [4:0] decL(input reg [5:0] dinL);
    case(dinL)
      6'b111001: decL = 0;
      6'b101110: decL = 1;
      6'b101101: decL = 2;
      6'b100011: decL = 3;
      6'b101011: decL = 4;
      6'b100101: decL = 5;
      6'b100110: decL = 6;
      6'b000111: decL = 7;
      6'b100111: decL = 8;
      6'b101001: decL = 9;
      6'b101010: decL = 10;
      6'b001011: decL = 11;
      6'b101100: decL = 12;
      6'b001101: decL = 13;
      6'b001110: decL = 14;
      6'b111010: decL = 15;
      6'b110110: decL = 16;
      6'b110001: decL = 17;
      6'b110010: decL = 18;
      6'b010011: decL = 19;
      6'b110100: decL = 20;
      6'b010101: decL = 21;
      6'b010110: decL = 22;
      6'b010111: decL = 23;
      6'b110011: decL = 24;
      6'b011001: decL = 25;
      6'b011010: decL = 26;
      6'b011011: decL = 27;
      6'b011100: decL = 28;
      6'b011101: decL = 29;
      6'b011110: decL = 30;
      6'b110101: decL = 31;
      6'b000110: decL = 0;
      6'b010001: decL = 1;
      6'b010010: decL = 2;
      6'b010100: decL = 4;
      6'b111000: decL = 7;
      6'b011000: decL = 8;
      6'b000101: decL = 15;
      6'b001001: decL = 16;
      6'b101000: decL = 23;
      6'b001100: decL = 24;
      6'b100100: decL = 27;
      6'b100010: decL = 29;
      6'b100001: decL = 30;
      6'b001010: decL = 31;
    endcase
  endfunction
  // 3/4 Encode
  function [2:0] decU(input reg [3:0] dinU);
    case(dinU)
      4'b1101: decU = 0;
      4'b1001: decU = 1;
      4'b1010: decU = 2;
      4'b0011: decU = 3;
      4'b1011: decU = 4;
      4'b0101: decU = 5;
      4'b0110: decU = 6;
      4'b0111: decU = 7;
      4'b1110: decU = 7;
      4'b0010: decU = 0;
      4'b1100: decU = 3;
      4'b0100: decU = 4;
      4'b1000: decU = 7;
      4'b0001: decU = 7;
    endcase
  endfunction
  function [7:0] decode(input reg [9:0] din);
    reg [7:0] dec_out;
    dec_out[4:0] = decL(din[5:0]);
    dec_out[7:5] = decU(din[9:6]);
    decode       = dec_out; 
  endfunction

  assign pushByte = pushB;
  assign Byte     = Bout;
  assign lastByte = lastB;
  assign Sync     = Syncout;

  // Comb logic for push out state machine
  always @(*) begin 
    pushB_d   = pushB;
    Syncout_d = Syncout;
    Bout_d    = Bout;
    Boutp_d   = Boutp;
    lastB_d    = lastB;
    st_push_d = st_push;
    case (st_push)
      0: begin // IDLE
        pushB_d   = 0;
        Syncout_d = 0;
        Bout_d    = 0;
//        Boutp_d   = 0;
        lastB_d   = 0;
        st_push_d = 0;
        if ((push_6==1) && (cnt==250)) begin
          pushB_d   = (Bcnt!=0) ? 1:0;
          Bout_d    = Boutp;
          Boutp_d   = decode(dec_in);
          Syncout_d = (Bcnt==1) ? 1:0;
          lastB_d = ((dec_in==10'h143) || (dec_in==10'h2BC)) ? 1:0;
          st_push_d = 1;
        end
      end
      1: begin // SYNC & PUSHB
        if (!stopIn) begin
          pushB_d   = 0;
          Syncout_d = 0;
          lastB_d   = 0;
          st_push_d = 0;
        end
      end
    endcase
  end

  always @(*) begin
    next_state = state;
    cnt_d      = cnt;
    Bcnt_d     = Bcnt;
    case (state)
      0: begin// Wait for sync signal
        cnt_d     = 0;
        Bcnt_d    = 0;
        if (sync_sig && push_6) begin
          next_state = 1;
        end
      end
      1: begin
        // We want 10 samples of 25 dumped samples between them: 25*10
        if (push_5 && (cnt<250)) begin //////////////////
          cnt_d   = cnt + 1;
        end
        else if (push_6 && (cnt==250)) begin
          cnt_d     = 0;
          Bcnt_d    = Bcnt + 1;
          if ((dec_in==10'h143) || (dec_in==10'h2BC)) begin
            next_state = 2;
          end else begin
            next_state = 1;
          end
        end
      end
      2: begin
        next_state = 0;
      end
    endcase
  end

  always @(*) begin
    dec_in_d = dec_in;
    case (cnt)

      12:  dec_in_d[0] = ~filt_cos_out[31];
      37:  dec_in_d[1] = ~filt_cos_out[31];
      62:  dec_in_d[2] = ~filt_cos_out[31];
      87:  dec_in_d[3] = ~filt_cos_out[31];
      112: dec_in_d[4] = ~filt_cos_out[31];
      137: dec_in_d[5] = ~filt_cos_out[31];
      162: dec_in_d[6] = ~filt_cos_out[31];
      187: dec_in_d[7] = ~filt_cos_out[31];
      212: dec_in_d[8] = ~filt_cos_out[31];
      237: dec_in_d[9] = ~filt_cos_out[31];

/*
      12:  dec_in_d[0] = filt_cos_out[31];
      37:  dec_in_d[1] = filt_cos_out[31];
      62:  dec_in_d[2] = filt_cos_out[31];
      87:  dec_in_d[3] = filt_cos_out[31];
      112: dec_in_d[4] = filt_cos_out[31];
      137: dec_in_d[5] = filt_cos_out[31];
      162: dec_in_d[6] = filt_cos_out[31];
      187: dec_in_d[7] = filt_cos_out[31];
      212: dec_in_d[8] = filt_cos_out[31];
      237: dec_in_d[9] = filt_cos_out[31];
*/
    endcase
  end

  always @ (negedge clk or posedge reset) begin
    if (reset) begin
      state   <= #1 0;
      cnt     <= #1 0;
      dec_in  <= #1 0;
      pushB   <= #1 0;
      Bout    <= #1 0;
      Boutp   <= #1 0;
      lastB   <= #1 0;
      Syncout <= #1 0;
      Bcnt    <= #1 0;
      st_push <= #1 0;
    end
    else begin
      state   <= #1 next_state;
      cnt     <= #1 cnt_d;
      dec_in  <= #1 dec_in_d;
      pushB   <= #1 pushB_d;
      Bout    <= #1 Bout_d;
      Boutp   <= #1 Boutp_d;
      lastB   <= #1 lastB_d;
      Syncout <= #1 Syncout_d;
      Bcnt    <= #1 Bcnt_d;
      st_push <= #1 st_push_d;
    end
  end
/*State machine for decoding*/

  always @(negedge clk or posedge reset) begin
    if(reset) begin
      push_0  <= #1 0;
      push_1  <= #1 0;
      push_2  <= #1 0;
      push_3  <= #1 0;
      push_4  <= #1 0;
      push_5  <= #1 0;
      push_6  <= #1 0;
      push_7  <= #1 0;
      push_8  <= #1 0;
      push_9  <= #1 0;
      push_10 <= #1 0;
      push_11 <= #1 0;
    end else begin
      push_0  <= #1 pushADC;
      push_1  <= #1 push_0;
      push_2  <= #1 push_1;
      push_3  <= #1 push_2;
      push_4  <= #1 push_3;
      push_5  <= #1 push_4;
      push_6  <= #1 push_5;
      push_7  <= #1 push_6;
      push_8  <= #1 push_7;
      push_9  <= #1 push_8;
      push_10 <= #1 push_9;
      push_11 <= #1 push_10;
    end
  end

  always @(negedge clk or posedge reset) begin
    if (reset) begin
      ADC_0 <= #1 0;
      nco   <= #1 0;
      phase <= #1 429496729;
//      phase <= #1 0;
    end
    else begin
      if (push_0) begin
        ADC_0 <= #1 ADC;
      end
      nco   <= #1 nco_d;
      phase <= #1 phase_d;
    end
  end
endmodule
