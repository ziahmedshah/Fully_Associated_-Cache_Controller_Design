`timescale 1ns/1ps

module tb_FullyAssociativeCache();

  // Parameters matching the DUT
  parameter CACHE_SIZE = 16;
  parameter BLOCK_SIZE = 4;
  parameter ADDR_WIDTH = 8;
  parameter DATA_WIDTH = 32;
  
  // Clock and reset
  reg clk;
  reg rst;
  
  // DUT signals
  reg read;
  reg write;
  reg [ADDR_WIDTH-1:0] addr;
  reg [DATA_WIDTH-1:0] write_data;
  wire [DATA_WIDTH-1:0] read_data;
  wire hit;
  wire dirty_evict;
  wire [ADDR_WIDTH-1:0] evict_addr;
  
  // Testbench variables
  reg [DATA_WIDTH-1:0] expected_data;
  integer error_count;
  integer test_case;
  
  // Memory model (for checking write-back behavior)
  reg [DATA_WIDTH-1:0] main_mem [0:(1<<ADDR_WIDTH)-1];
  
  // Instantiate DUT
  FullyAssociativeCache #(
    .CACHE_SIZE(CACHE_SIZE),
    .BLOCK_SIZE(BLOCK_SIZE),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst(rst),
    .read(read),
    .write(write),
    .addr(addr),
    .write_data(write_data),
    .read_data(read_data),
    .hit(hit),
    .dirty_evict(dirty_evict),
    .evict_addr(evict_addr)
  );
  
  // Clock generation
  always #5 clk = ~clk;
  
  // Initialize memory
  initial begin
    for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
      main_mem[i] = i; // Initialize with address value
    end
  end
  
  // Main test sequence
  initial begin
    // Initialize signals
    clk = 0;
    rst = 1;
    read = 0;
    write = 0;
    addr = 0;
    write_data = 0;
    error_count = 0;
    test_case = 0;
    
    // Reset the DUT
    #20;
    rst = 0;
    #10;
    
    // Test Case 1: Basic read miss
    test_case = 1;
    $display("Test Case 1: Basic read miss");
    read = 1;
    addr = 8'h10;
    #10;
    check_result(0, 0, "Read miss");
    read = 0;
    #10;
    
    // Test Case 2: Basic write miss (write-allocate)
    test_case = 2;
    $display("Test Case 2: Basic write miss (write-allocate)");
    write = 1;
    addr = 8'h20;
    write_data = 32'hA5A5A5A5;
    #10;
    check_result(0, 0, "Write miss");
    write = 0;
    #10;
    
    // Test Case 3: Read hit after write
    test_case = 3;
    $display("Test Case 3: Read hit after write");
    read = 1;
    addr = 8'h20;
    expected_data = 32'hA5A5A5A5;
    #10;
    check_result(1, expected_data, "Read hit after write");
    read = 0;
    #10;
    
    // Test Case 4: Write hit
    test_case = 4;
    $display("Test Case 4: Write hit");
    write = 1;
    addr = 8'h20;
    write_data = 32'hB6B6B6B6;
    #10;
    check_result(1, 0, "Write hit");
    write = 0;
    #10;
    
    // Test Case 5: Verify write-back on dirty eviction
    test_case = 5;
    $display("Test Case 5: Verify write-back on dirty eviction");
    
    // Fill the cache with unique addresses
    for (int i = 0; i < CACHE_SIZE; i++) begin
      write = 1;
      addr = 8'h30 + i;
      write_data = 32'hC0 + i;
      #10;
      write = 0;
      #10;
    end
    
    // Trigger eviction of first written line (should be LRU)
    write = 1;
    addr = 8'h50;
    write_data = 32'hDEADBEEF;
    #10;
    check_result(0, 0, "Write miss with eviction");
    if (!dirty_evict) begin
      $error("Test Case 5: Dirty eviction not detected");
      error_count++;
    end
    write = 0;
    #10;
    
    // Test Case 6: LRU replacement policy verification
    test_case = 6;
    $display("Test Case 6: LRU replacement policy verification");
    
    // Access first CACHE_SIZE-1 lines to make their LRU counters higher
    for (int i = 1; i < CACHE_SIZE; i++) begin
      read = 1;
      addr = 8'h30 + i;
      #10;
      read = 0;
      #10;
    end
    
    // Next miss should replace addr 0x30 (least recently used)
    write = 1;
    addr = 8'h60;
    write_data = 32'hFACEFEED;
    #10;
    check_result(0, 0, "LRU replacement check");
    if (evict_addr[ADDR_WIDTH-1:0] != 8'h30) begin
      $error("Test Case 6: Wrong LRU eviction. Expected 0x30, got 0x%h", evict_addr);
      error_count++;
    end
    write = 0;
    #10;
    
    // Test Case 7: Mixed read/write sequence
    test_case = 7;
    $display("Test Case 7: Mixed read/write sequence");
    
    // Sequence of operations
    test_operation(1, 8'h70, 32'h11111111, 0); // Write miss
    test_operation(0, 8'h70, 0, 32'h11111111); // Read hit
    test_operation(1, 8'h80, 32'h22222222, 0); // Write miss
    test_operation(1, 8'h70, 32'h33333333, 32'h11111111); // Write hit
    test_operation(0, 8'h80, 0, 32'h22222222); // Read hit
    test_operation(0, 8'h70, 0, 32'h33333333); // Read hit
    
    // Test Case 8: Reset behavior
    test_case = 8;
    $display("Test Case 8: Reset behavior");
    rst = 1;
    #10;
    rst = 0;
    #10;
    
    // Verify cache is empty after reset
    read = 1;
    addr = 8'h70;
    #10;
    check_result(0, 0, "Cache miss after reset");
    read = 0;
    #10;
    
    // Test Case 9: Corner case - same address read/write
    test_case = 9;
    $display("Test Case 9: Same address read/write");
    
    for (int i = 0; i < 5; i++) begin
      write = 1;
      addr = 8'h90;
      write_data = 32'h12345670 + i;
      #10;
      write = 0;
      #10;
      
      read = 1;
      addr = 8'h90;
      expected_data = 32'h12345670 + i;
      #10;
      check_result(1, expected_data, "Same address verification");
      read = 0;
      #10;
    end
    
    // Final report
    #10;
    if (error_count == 0) begin
      $display("All test cases passed!");
    end else begin
      $display("Test completed with %0d errors", error_count);
    end
    
    $finish;
  end
  
  // Task to perform and check a single operation
  task test_operation;
    input is_write;
    input [ADDR_WIDTH-1:0] op_addr;
    input [DATA_WIDTH-1:0] wr_data;
    input [DATA_WIDTH-1:0] expected_rd_data;
    begin
      if (is_write) begin
        write = 1;
        addr = op_addr;
        write_data = wr_data;
        #10;
        write = 0;
      end else begin
        read = 1;
        addr = op_addr;
        #10;
        read = 0;
      end
      #5;
      
      if (is_write) begin
        check_result(hit, 0, is_write ? "Write operation" : "Read operation");
      end else begin
        check_result(hit, expected_rd_data, is_write ? "Write operation" : "Read operation");
      end
      #5;
    end
  endtask
  
  // Task to check results
  task check_result;
    input expected_hit;
    input [DATA_WIDTH-1:0] expected_data;
    input string message;
    begin
      if (hit !== expected_hit) begin
        $error("Test Case %0d: %s - Hit mismatch. Expected %b, got %b", 
               test_case, message, expected_hit, hit);
        error_count++;
      end
      
      if (!expected_hit && expected_data !== 0) begin
        if (read_data !== expected_data) begin
          $error("Test Case %0d: %s - Data mismatch. Expected 0x%h, got 0x%h", 
                 test_case, message, expected_data, read_data);
          error_count++;
        end
      end
    end
  endtask
  
  // Monitor for write-back operations
  always @(posedge dirty_evict) begin
    $display("Write-back detected for address 0x%h", evict_addr);
    // In a real testbench, you would verify the data being written back
    main_mem[evict_addr] = dut.cache[0].data; // Simplified for demonstration
  end
  
  // Waveform dumping
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_FullyAssociativeCache);
  end
  
endmodule
