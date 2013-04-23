/* This module keeps a FIFO filled that then outputs to the DVI module. */

module PixelFeeder( //System:
                    input          cpu_clk_g,
                    input          clk50_g, // DVI Clock
                    input          rst,
                    //Video buffer input:
                    input             vram_valid,
                    output            vram_ready,
                    input      [31:0] vram_dout,
                    input      [95:0] color_map,
                    // DVI module:
                    output [23:0]  video,
                    output         video_valid,
                    input          video_ready);

    // Hint: States
    localparam IDLE = 1'b0;
    localparam FETCH = 1'b1;

    reg  [31:0] ignore_count;
    wire [3:0] feeder_dout;
    wire feeder_full;
    wire feeder_empty;
    wire blanking; // no video data available
    reg feedhalf; // fifo has min output width of 4, so feedhalf tells us which half of the output to use
    reg [1:0] color_idx;
    reg [23:0] color;

    /**************************************************************************
    * YOUR CODE HERE: Write logic to keep the FIFO as full as possible.
    **************************************************************************/


    //* We drop the first frame to allow the buffer to fill with data from
    // DDR2. This gives alignment of the frame. 
    always @(posedge cpu_clk_g) begin
       if(rst) begin
            ignore_count <= 32'd480000; // 600*800 
            feedhalf <= 0;
       end
       else if(ignore_count != 0 & video_ready) begin
            ignore_count <= ignore_count - 32'b1;
            feedhalf <= ~feedhalf;
       end
       else begin
            ignore_count <= ignore_count;
            feedhalf <= ~feedhalf;
       end
    end

    always @(*) begin
        color_idx = feedhalf ? feeder_dout[1:0] : feeder_dout[3:2];
        case (color_idx)
          0: color = color_map[23:0];
          1: color = color_map[47:24];
          2: color = color_map[71:48];
          3: color = color_map[95:72];
        endcase
    end

    // FIFO to buffer the reads with a write width of 32 and read width of 2. We try to fetch blocks
    // until the FIFO is full.
    pixel_fifo feeder_fifo(
    	.rst(rst),
    	.wr_clk(cpu_clk_g),
    	.rd_clk(clk50_g),
    	.din(vram_dout[31:0]),
    	.wr_en(vram_valid),
    	.rd_en(video_ready & ignore_count == 0 & feedhalf),
    	.dout(feeder_dout),
    	.full(feeder_full),
    	.empty(feeder_empty));

    assign blanking = feeder_empty | ignore_count != 0;

    assign video = blanking ? 24'b0 : color[23:0];
    assign video_valid = 1'b1;


//assign video = 24'h00ffff;
//assign video_valid = 1;

//assign rdf_rd_en = 0;
//assign af_wr_en = 0;
//assign af_addr_din = 31'b0;


endmodule
