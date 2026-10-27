// sentinel.cl — minimal kernel exercising 64-bit indexing across the 4 GiB boundary.
// Build WITHOUT -cl-intel-greater-than-4GB-buffer-required for the stateful/default case,
// and WITH it for the stateless/large-buffer case. The source is identical; only the
// build flag and the allocation mode differ between cases.
//
// Element type is ulong (64-bit). Indices and the PRNG mirror the CPU oracle exactly
// (SplitMix64), so host and device must agree bit-for-bit.

inline ulong splitmix64(ulong state) {
  ulong z = (state + 0x9E3779B97F4A7C15UL);
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
  return z ^ (z >> 31);
}

inline ulong expected_value(ulong seed, ulong element_index) {
  ulong state = seed ^ (element_index * 0xD1B54A32D192ED03UL);
  return splitmix64(state);
}

// Write the expected value at each global element index. `n_elems` is 64-bit.
__kernel void sentinel_write(__global ulong *buf, const ulong seed, const ulong n_elems) {
  ulong gid = (ulong)get_global_id(0);
  if (gid < n_elems) {
    buf[gid] = expected_value(seed, gid);
  }
}

// Verify a sparse set of element indices on the device; flag[0] accumulates mismatches.
__kernel void sentinel_check(__global const ulong *buf,
                             __global const ulong *indices,
                             const ulong n_indices,
                             const ulong seed,
                             __global ulong *mismatch_count) {
  ulong gid = (ulong)get_global_id(0);
  if (gid < n_indices) {
    ulong idx = indices[gid];
    if (buf[idx] != expected_value(seed, idx)) {
      atom_add(mismatch_count, 1UL);
    }
  }
}
