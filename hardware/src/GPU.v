module GPU(
    input clk,
    input rst,

    input        dv,
    input [31:0] din,
    output ready,

    // DVI
    output [23:0] video,
    output        video_valid,
    input         video_ready
    );

    localparam WIDTH = 800;
    localparam HEIGHT = 600;
    localparam DEPTH = 2; // bits per pixel
    
    // FSM state
    localparam Idle = 0; 
    localparam ReadInputs = 1;
    localparam Busy = 2;
    reg [1:0] state;
    
    // commands
    localparam Swap = 0;            // Swap video buffers
    localparam ChangeColorMap = 1;  // Change color values
    localparam Pixel = 2;           // Set the color of a pixel
    localparam Rect = 3;            // Fill a rectangle
    reg [15:0] cmd;
    

    reg [DEPTH-1:0] color; // a command color, eg. fill color

    // #### Video buffers - low-level iface ####
    reg  [95:0] color_map;
    
    wire [18:0] ra0;
    wire [31:0] rd0;
    wire [18:0] wa0;
    wire [31:0] wd0;
    wire        we0;

    wire [18:0] ra1;
    wire [31:0] rd1;
    wire [18:0] wa1;
    wire [31:0] wd1;
    wire        we1;

    vram vbuf0({
        .clk(clk),
        .ra(ra0),
        .rd(rd0),
        .wa(wa0),
        .wd(wd0),
        .we(we0)
    );
    vram vbuf1(
        .clk(clk),
        .ra(ra1),
        .rd(rd1),
        .wa(wa1),
        .wd(wd1),
        .we(we1)
    );

    // #### Video buffers - high-level iface ####
    reg         vramSel; // which buffer is the work; other one is displayed
   
    // PixelFeeder - This goes directly to the DVI module
    localparam A_MAX = WIDTH*HEIGHT/(32/DEPTH) - 1; // Maximum VRAM addr
    wire pf_ready;
    reg  [18:0] pfa; // VRAM address
    wire [31:0] pfd; // VRAM data
    PixelFeeder pf(
        .cpu_clk_g(clk),
        .clk50_g(clk),
        .rst(rst),
        .vram_valid(~rst),
        .vram_ready(pf_ready),
        .vram_dout(pfd),
        .color_map(color_map),
        .video(video),             // -> DVI
        .video_valid(video_valid), // -> DVI
        .video_ready(video_ready)  // <- DVI
    );


    // These will point the working buffer, while the other buffer is displayed
    reg  [18:0] ra;
    wire [31:0] rd;
    reg  [18:0] wa;
    reg  [31:0] wd;
    reg         we;

    // Video buffers - connections b/w high and low level
    assign ra0 =   (vramSel  == 0) ? ra:pfa;
    assign ra1 =   (vramSel  == 1) ? ra:pfa;
    assign rd  =   (vramSel  == 0) ? rd0:rd1;
    assign pfd = (vramSel !== 0) ? rd0:rd1;
    assign wa0 = wa;
    assign wa1 = wa;
    assign wd0 = wd;
    assign wd1 = wd;
    assign we0 = (vramSel == 0) & we; 
    assign we1 = (vramSel == 1) & we;


    initial color_map = 96'hffffff_00ffff_ff0000_000000;


    reg [18:0] i;
    reg [9:0] x[1:0];
    reg [9:0] y[1:0];
    reg [9:0] w;
    reg [9:0] h;

    // #### Helper variables ####
    // (x[0],y[0]) is the first pixel in the row
    // (x[1],y[1]) is the current pixel
    reg [5:0] xStride;         // how many pixels to skip ahead, along the x-axis
    reg       rowDone;         // whether to skip to the next row

    wire [18:0] xy[1:0];       // word addr of (x[0],y[0]) and (x[1],y[1])
    wire [18:0] xyMax;         // word addr of end of w-sized row, starting @(x[0],y[0])
    wire [4:0] xyb[1:0];       // bit addr  of (x[0],y[0]) and (x[1],y[1])
    wire [4:0] xybMax;         // bit addr  of end of w-sized row, starting @(x[0],y[0])

    reg [31:0] modPxData;      // word for plotting a pixel
    reg [31:0] modBlockData;   // word for filling a rect


    `define WADDR(X,Y) (((X)+(Y)*WIDTH)>>(5-DEPTH+1)) // word addr of (x,y)
    `define BADDR(X)   (DEPTH*((X)%(32/DEPTH)))   // bit addr of (x,y) within word
    assign xy[0] =  WADDR(x[0],y[0]); 
    assign xy[1] =  WADDR(x[1],y[1]);
    assign xyMax =  WADDR(x[0]+w-1,y[0]);         // end of current row
    assign xyb[0] = BADDR(x[0],y[0]);
    assign xyb[1] = BADDR(x[1],y[1]);
    assign xybMax = BADDR(x[0]+w-1,y[0]);         // end of current row


    always @(*) begin
        xStride = (32-xyb[1])/DEPTH;  // try to jump to word boundary
        rowDone = 1;

        // #### Pixel ####
        modPxData = rd;                     // get the old word
        modPxData[xyb[0]+DEPTH-1:xyb[0]] = color; // change the pixel in the word

        // #### Rect fill ####
        if (x[1] >= WIDTH) rowDone = 1;

        /* Had to remove this elegant code; verilog doesn't allow
         * replication by a variable, only by a constant.
         * Retained to explain what is happening in the code following
         * this comment.

        modBlockData = rd;
        if (xy[0] == xyMax) begin               // first word == last word
            modBlockData[xybMax+1:xyb[0]] = {w{color}};
        end
        else if (xy[1] == xyMax) begin          // row end
            modBlockData[xybMax+1:0] = {(xybMax/2){color}};
        end
        else begin                              // row start or middle
            modBlockData[31:xyb[1]] = {xStride{color}};
            rowDone = 0;
        end
        //*/
        modRectData = rd;
        if (xy[0] == xyMax) begin               // row begins and ends in same word
            `define MODRECT_BIT(B) \
                if (xyb[0] <= (B) && (B) <= xybMax) modRectData[(B)+1:(B)] = color
            MODRECT_BIT(0);
            MODRECT_BIT(2);
            MODRECT_BIT(4);
            MODRECT_BIT(6);
            MODRECT_BIT(8);
            MODRECT_BIT(10);
            MODRECT_BIT(12);
            MODRECT_BIT(14);
            MODRECT_BIT(16);
            MODRECT_BIT(18);
            MODRECT_BIT(20);
            MODRECT_BIT(22);
            MODRECT_BIT(24);
            MODRECT_BIT(26);
            MODRECT_BIT(28);
            MODRECT_BIT(30);
        end
        else if (xy[1] == xyMax) begin          // row end
            `define MODRECT_BIT(B) \
                if ((B) <= xybMax) modRectData[(B)+1:(B)] = color
            MODRECT_BIT(0);
            MODRECT_BIT(2);
            MODRECT_BIT(4);
            MODRECT_BIT(6);
            MODRECT_BIT(8);
            MODRECT_BIT(10);
            MODRECT_BIT(12);
            MODRECT_BIT(14);
            MODRECT_BIT(16);
            MODRECT_BIT(18);
            MODRECT_BIT(20);
            MODRECT_BIT(22);
            MODRECT_BIT(24);
            MODRECT_BIT(26);
            MODRECT_BIT(28);
            MODRECT_BIT(30);
        end
        else begin                              // row start or middle
            `define MODRECT_BIT(B) \
                if ((B) >= xyb[1]) modRectData[(B)+1:(B)] = color
            MODRECT_BIT(0);
            MODRECT_BIT(2);
            MODRECT_BIT(4);
            MODRECT_BIT(6);
            MODRECT_BIT(8);
            MODRECT_BIT(10);
            MODRECT_BIT(12);
            MODRECT_BIT(14);
            MODRECT_BIT(16);
            MODRECT_BIT(18);
            MODRECT_BIT(20);
            MODRECT_BIT(22);
            MODRECT_BIT(24);
            MODRECT_BIT(26);
            MODRECT_BIT(28);
            MODRECT_BIT(30);
            rowDone = 0;
        end
    end


    assign ready = state == Idle;
    
    
    always @(posedge clk) begin
        if (rst) begin
            state <= Idle;
        end
        else begin
            if (pf_ready) begin                     // Keep PixelFeeder happy
                if (pfa < A_MAX) pfa <= pfa + 1;
                else             pfa <= 0;
            end

            case (state)                            // FSM
            Idle: begin
                ra <= 0;
                wa <= 0;
                wd <= 0;
                we <= 0;
                i  <= 0;
                x[0] <= 0;
                y[0] <= 0;
                x[1] <= 0;
                y[1] <= 0;
                w <= 0;
                h <= 0;

                if (dv) begin
                    state <= ReadInputs;
                    cmd <= din[15:0];
                    color <= din[16+DEPTH-1:16];
                end
            end

            ReadInputs: begin
                case (cmd)
                Swap: begin
                    if (pfa == A_MAX) begin
                        vramSel <= ~vramSel;
                        state <= Idle;
                    end
                end

                ChangeColorMap: begin
                    i <= i+1;
                    if (i == 3) state <= Idle;
                    
                    case (i)
                    0: color_map[23:0]  <= din[23:0];
                    1: color_map[47:24] <= din[23:0];
                    2: color_map[71:48] <= din[23:0];
                    3: color_map[95:72] <= din[23:0];
                    default: state <= Idle;
                    endcase
                end

                Pixel: begin 
                    x[0] <= din[9:0];
                    y[0] <= din[25:16];

                    // validate x and y
                    if (din[9:0] >= WIDTH || din[25:16] >= HEIGHT) state <= Idle;
                    else begin
                        ra <= WADDR(din[9:0],din[25:16]);
                        wa <= WADDR(din[9:0],din[25:16]);

                        state <= Busy;
                    end
                end
//*
                Rect: begin
                    i <= i+1;
                    case (i)
                    0: begin
                        x[0] <= din[9:0];
                        y[0] <= din[25:16];
                    end
                    1: begin
                        w <= din[9:0];  
                        h <= din[25:16];

                        x[1] <= x[0];
                        y[1] <= y[0];
                        
                        // validate x and y
                        if (x[0] >= WIDTH && y[0] >= HEIGHT) state <= Idle;
                        else begin 
                            state <= Busy;
                            i <= 0;
                        end
                    end
                    default: state <= Idle;
                    endcase
                end
//*/
                default: state <= Idle;
                endcase // (cmd)
            end // ReadInputs

            Busy: begin
                case (cmd)
                Pixel: begin
                    wd <= modPxData;
                    we <= 1;
                    state <= Idle;
                end
                
                Rect: begin
                    if (h == 0) state <= Idle;
                    else begin
                        wd <= modRectData;
                        we <= 1;
                        ra <= xy[1];
                        wa <= xy[1];
                        if (rowDone) begin
                            h <= h-1;
                            y[0] <= y[0]+1;
                            y[1] <= y[0]+1;
                            x[1] <= x[0];
                        end
                        else begin
                            x[1] <= x[1] + xStride;
                        end
                    end
                end
                default: state <= Idle;
                endcase
            end
            endcase
    end

endmodule
