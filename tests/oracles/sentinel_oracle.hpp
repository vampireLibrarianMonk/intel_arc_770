// sentinel_oracle.hpp — independent CPU reference for the >4 GiB correctness harness.
// Header-only, no OpenCL dependency, so it compiles and is unit-testable offline.
#pragma once

#include <cstdint>
#include <vector>

namespace arc_oracle {

// Deterministic SplitMix64 PRNG: same seed -> same stream on host and in-kernel reference.
inline std::uint64_t splitmix64(std::uint64_t &state) {
  std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
  return z ^ (z >> 31);
}

// Expected sentinel value written at a given element index for a given seed.
// Mirrors exactly what sentinel.cl must compute on the device.
inline std::uint64_t expected_value(std::uint64_t seed, std::uint64_t element_index) {
  std::uint64_t state = seed ^ (element_index * 0xD1B54A32D192ED03ULL);
  return splitmix64(state);
}

// Byte offsets that must be exercised around the 4 GiB boundary (and edges).
// `buffer_bytes` lets us clamp to valid, in-bounds offsets for the chosen size.
inline std::vector<std::uint64_t> sentinel_byte_offsets(std::uint64_t buffer_bytes,
                                                        std::uint64_t elem_size) {
  const std::uint64_t G4 = 1ULL << 32;  // 2^32 bytes == 4 GiB
  std::vector<std::uint64_t> offs;
  const std::uint64_t candidates[] = {
      0ULL,
      G4 - elem_size,       // just below 4 GiB
      G4,                   // exactly at 4 GiB
      G4 + 4096ULL,         // just past 4 GiB
  };
  for (std::uint64_t c : candidates) {
    if (c + elem_size <= buffer_bytes) offs.push_back(c);
  }
  // Always include the last valid element.
  if (buffer_bytes >= elem_size) offs.push_back(buffer_bytes - elem_size);
  return offs;
}

// Order-independent digest so a device-side digest can be cross-checked cheaply.
inline std::uint64_t digest(std::uint64_t seed, std::uint64_t element_count) {
  std::uint64_t acc = 0;
  for (std::uint64_t i = 0; i < element_count; ++i) {
    acc += expected_value(seed, i);  // wrapping add; commutative
  }
  return acc;
}

}  // namespace arc_oracle
