// addr_bench.cl — workloads for the stateless-vs-stateful addressing cost study (H2).
// Same source for both paths; only the build flag (-cl-intel-greater-than-4GB-buffer-required)
// and the allocation mode differ. Element type is ulong (64-bit), 64-bit indices throughout.

inline ulong splitmix64(ulong state) {
  ulong z = (state + 0x9E3779B97F4A7C15UL);
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
  return z ^ (z >> 31);
}

// W1 — address-generation-heavy: short compute, frequent indexed stores.
__kernel void w_addr(__global ulong *buf, const ulong n) {
  ulong gid = (ulong)get_global_id(0);
  if (gid < n) buf[gid] = gid * 2654435761UL + 1UL;
}

// W2 — bandwidth-bound streaming: read a, write 2a, sequential.
__kernel void w_stream(__global const ulong *in, __global ulong *out, const ulong n) {
  ulong gid = (ulong)get_global_id(0);
  if (gid < n) out[gid] = in[gid] * 2UL;
}

// W3 — random-access: scatter reads across the whole buffer (incl. past 4 GiB).
__kernel void w_random(__global const ulong *buf, __global ulong *out, const ulong n) {
  ulong gid = (ulong)get_global_id(0);
  if (gid < n) {
    ulong j = splitmix64(gid) % n;      // 64-bit index anywhere in the buffer
    out[gid] = buf[j];
  }
}
