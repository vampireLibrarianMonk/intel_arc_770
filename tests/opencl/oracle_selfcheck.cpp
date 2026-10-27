// oracle_selfcheck.cpp — offline unit check for the CPU oracle.
// Builds and runs with NO OpenCL and NO GPU, so the harness stays CI-green on any host.
#include <cstdint>
#include <cstdio>

#include "../oracles/sentinel_oracle.hpp"

int main() {
  int failures = 0;

  // 1. Determinism: same seed/index -> same value.
  if (arc_oracle::expected_value(123456ULL, 42ULL) !=
      arc_oracle::expected_value(123456ULL, 42ULL)) {
    std::printf("FAIL: expected_value not deterministic\n");
    ++failures;
  }

  // 2. Distinct indices should (overwhelmingly) produce distinct values.
  if (arc_oracle::expected_value(123456ULL, 1ULL) ==
      arc_oracle::expected_value(123456ULL, 2ULL)) {
    std::printf("FAIL: collision on trivially different indices\n");
    ++failures;
  }

  // 3. Boundary offsets must include points at/above 4 GiB for a >4 GiB buffer.
  const std::uint64_t G4 = 1ULL << 32;
  auto offs = arc_oracle::sentinel_byte_offsets(G4 + (1ULL << 20), sizeof(std::uint64_t));
  bool has_at_or_above_4g = false;
  for (std::uint64_t o : offs) {
    if (o >= G4) has_at_or_above_4g = true;
  }
  if (!has_at_or_above_4g) {
    std::printf("FAIL: no sentinel offset at or above the 4 GiB boundary\n");
    ++failures;
  }

  // 4. Digest is stable for a fixed seed/count.
  if (arc_oracle::digest(7ULL, 1000ULL) != arc_oracle::digest(7ULL, 1000ULL)) {
    std::printf("FAIL: digest not stable\n");
    ++failures;
  }

  if (failures == 0) {
    std::printf("oracle_selfcheck: ALL PASS\n");
    return 0;
  }
  std::printf("oracle_selfcheck: %d failure(s)\n", failures);
  return 1;
}
