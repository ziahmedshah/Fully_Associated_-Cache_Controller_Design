/*
 * Engineer : Zia Ahmed Shah
 * Date : 17-03-2025
 * Fully Associative Cache Module
 * Features:
 * - FULLY ASSOCIATIVE MAPPING (Any block can go in any line)
 * - WRITE-ALLOCATE POLICY (On write miss, allocate line then write)
 * - WRITE-BACK POLICY (Only write to memory when line is evicted)
 * - LRU REPLACEMENT POLICY (Least Recently Used eviction)
 * - SYNCHRONOUS DESIGN (All operations clocked)
 * - PARAMETERIZED CONFIGURATION (Size, width customizable)
 */

module FullyAssociativeCache #(
  parameter CACHE_SIZE = 16,    // Number of cache lines
  parameter BLOCK_SIZE = 4,     // Bytes per block (must be power of 2)
  parameter ADDR_WIDTH = 8,     // Address bus width
  parameter DATA_WIDTH = 32     // Data bus width
)(
  input wire clk,                      // Clock signal
  input wire rst,                      // Reset signal
  input wire read,                     // Read request
  input wire write,                    // Write request
  input wire [ADDR_WIDTH-1:0] addr,     // Address for read/write
  input wire [DATA_WIDTH-1:0] write_data, // Data to be written
  output reg [DATA_WIDTH-1:0] read_data, // Data read from cache
  output reg hit,                      // Hit signal (1 if cache hit, 0 if miss)
  output reg dirty_evict,               // Indicates if an evicted line was dirty
  output reg [ADDR_WIDTH-1:0] evict_addr // Address of evicted line (for write-back)
);

  // Calculate parameters for address breakdown
  localparam OFFSET_WIDTH = $clog2(BLOCK_SIZE); // Offset bits (within a block)
  localparam TAG_WIDTH = ADDR_WIDTH - OFFSET_WIDTH; // Tag bits (identifies memory block)
  localparam LRU_COUNTER_WIDTH = $clog2(CACHE_SIZE); // Bits needed for LRU counter

  // Define the structure for a cache line
  typedef struct packed {
    logic [TAG_WIDTH-1:0] tag;              // Tag to identify memory block
    logic valid;                            // Valid bit (1 if entry is valid)
    logic dirty;                            // Dirty bit (1 if modified)
    logic [LRU_COUNTER_WIDTH-1:0] lru_counter; // LRU counter (for replacement policy)
    logic [DATA_WIDTH-1:0] data;            // Data stored in cache
  } cache_line_t;

  // Cache memory array
  cache_line_t [CACHE_SIZE-1:0] cache;

  // Extracting tag and offset from the address
  wire [TAG_WIDTH-1:0] current_tag = addr[ADDR_WIDTH-1:OFFSET_WIDTH]; // Extract tag
  wire [OFFSET_WIDTH-1:0] current_offset = addr[OFFSET_WIDTH-1:0];   // Extract offset
  integer i; // Loop variable

  // Cache Operation: Reset, Read, Write, and LRU updates
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      // Reset all cache lines
      for (i = 0; i < CACHE_SIZE; i = i + 1) begin
        cache[i].valid <= 1'b0;         // Invalidate all cache lines
        cache[i].dirty <= 1'b0;         // Clear dirty bits
        cache[i].lru_counter <= LRU_COUNTER_WIDTH'(i); // Initialize LRU counters
        cache[i].tag <= {TAG_WIDTH{1'b0}}; // Reset tag
        cache[i].data <= {DATA_WIDTH{1'b0}}; // Clear data
      end
      hit <= 1'b0;          // Reset hit signal
      read_data <= {DATA_WIDTH{1'b0}}; // Reset read data
      dirty_evict <= 1'b0;  // Reset eviction signal
      evict_addr <= {ADDR_WIDTH{1'b0}}; // Reset eviction address
    end else begin
      // Default values for outputs
      hit <= 1'b0;
      dirty_evict <= 1'b0;
      evict_addr <= {ADDR_WIDTH{1'b0}};

      // Only proceed if a read or write request is given
      if (read || write) begin
        // Search for the requested address in the cache
        for (i = 0; i < CACHE_SIZE; i = i + 1) begin
          if (cache[i].valid && (cache[i].tag == current_tag)) begin
            // Cache Hit: Found the requested block
            hit <= 1'b1;

            // Read Operation: Return the stored data
            if (read) begin
              read_data <= cache[i].data;
            end

            // Write Operation: Update the cache data and set dirty bit
            if (write) begin
              cache[i].data <= write_data;
              cache[i].dirty <= 1'b1;
            end

            // Update LRU Counters: Set this line as most recently used
            cache[i].lru_counter <= {LRU_COUNTER_WIDTH{1'b0}};
            for (int j = 0; j < CACHE_SIZE; j = j + 1) begin
              if (j != i && cache[j].lru_counter < cache[i].lru_counter) begin
                cache[j].lru_counter <= cache[j].lru_counter + 1;
              end
            end

            break; // Stop searching since we found a hit
          end
        end

        // If no hit occurred, handle cache miss
        if (!hit) begin
          // Find the Least Recently Used (LRU) line for replacement
          integer lru_index = 0;
          logic [LRU_COUNTER_WIDTH-1:0] max_counter = cache[0].lru_counter;

          for (i = 1; i < CACHE_SIZE; i = i + 1) begin
            if (cache[i].lru_counter > max_counter) begin
              max_counter = cache[i].lru_counter;
              lru_index = i; // Select index with highest counter as LRU
            end
          end

          // Check if the LRU line is dirty (requires write-back)
          if (cache[lru_index].valid && cache[lru_index].dirty) begin
            dirty_evict <= 1'b1; // Indicate dirty eviction
            evict_addr <= {cache[lru_index].tag, current_offset}; // Set evicted address
          end

          // Allocate a new cache line (Write-Allocate Policy)
          cache[lru_index].valid <= 1'b1;  // Mark line as valid
          cache[lru_index].tag <= current_tag; // Store the new tag
          cache[lru_index].dirty <= write; // Mark dirty only if it's a write

          // Load data: For writes, store immediately; for reads, assume zero (simplified)
          if (write) begin
            cache[lru_index].data <= write_data;
          end else begin
            cache[lru_index].data <= {DATA_WIDTH{1'b0}}; // Placeholder for fetched memory data
          end

          // Update LRU counters: New line becomes most recently used
          cache[lru_index].lru_counter <= {LRU_COUNTER_WIDTH{1'b0}};
          for (i = 0; i < CACHE_SIZE; i = i + 1) begin
            if (i != lru_index && cache[i].lru_counter < max_counter) begin
              cache[i].lru_counter <= cache[i].lru_counter + 1;
            end
          end

          // For read misses, return the newly allocated data
          if (read) begin
            read_data <= cache[lru_index].data;
          end
        end
      end
    end
  end

endmodule
