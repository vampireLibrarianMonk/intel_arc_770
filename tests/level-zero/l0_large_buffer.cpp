// l0_large_buffer.cpp — Arc A770 >4 GiB Level Zero allocation probe.
//
// Mirrors the OpenCL harness for the L0 API. Confirms:
//   * default: a device allocation > CL_DEVICE_MAX_MEM_ALLOC_SIZE (~4 GiB) is refused
//   * with ze_relaxed_allocation_limits_exp_desc_t + ZE_..._FLAG_MAX_SIZE, a single
//     >4 GiB device buffer allocates, and sentinel bytes across the 4 GiB offset
//     round-trip correctly (copy up, copy back, compare on host)
//
// This probe verifies the ALLOCATION path (the hard part / the H0 boundary). It does not
// JIT a stateless kernel; the stateless module flag -ze-opt-greater-than-4GB-buffer-required
// is the compute-correctness half, already proven on the OpenCL side (MEM-05/06).
//
// No device => prints plan, exits 0. Build: see CMakeLists.txt.

#include <level_zero/ze_api.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {
constexpr std::uint64_t GiB = 1ULL << 30;

#define ZECHECK(call, what)                                              \
  do {                                                                   \
    ze_result_t _r = (call);                                             \
    if (_r != ZE_RESULT_SUCCESS) {                                       \
      std::printf("  %s failed: 0x%x\n", what, (unsigned)_r);            \
      return _r;                                                         \
    }                                                                    \
  } while (0)

struct Ctx {
  ze_driver_handle_t driver = nullptr;
  ze_device_handle_t device = nullptr;
  ze_context_handle_t context = nullptr;
};

bool find_a770(Ctx *c) {
  uint32_t nd = 0;
  if (zeDriverGet(&nd, nullptr) != ZE_RESULT_SUCCESS || nd == 0) return false;
  std::vector<ze_driver_handle_t> drivers(nd);
  zeDriverGet(&nd, drivers.data());
  for (auto drv : drivers) {
    uint32_t ndev = 0;
    if (zeDeviceGet(drv, &ndev, nullptr) != ZE_RESULT_SUCCESS || ndev == 0) continue;
    std::vector<ze_device_handle_t> devs(ndev);
    zeDeviceGet(drv, &ndev, devs.data());
    for (auto d : devs) {
      ze_device_properties_t p = {ZE_STRUCTURE_TYPE_DEVICE_PROPERTIES};
      zeDeviceGetProperties(d, &p);
      std::string n(p.name);
      if (p.type == ZE_DEVICE_TYPE_GPU &&
          (n.find("A770") != std::string::npos || n.find("Arc") != std::string::npos)) {
        c->driver = drv; c->device = d;
        std::printf("Device: %s\n", p.name);
        return true;
      }
    }
  }
  return false;
}

// Try a single device allocation of `bytes`, with or without the relaxed-limits flag.
// Returns the ze_result_t from zeMemAllocDevice (ZE_RESULT_SUCCESS == allocated).
ze_result_t try_alloc(const Ctx &c, std::uint64_t bytes, bool relaxed, void **out) {
  ze_device_mem_alloc_desc_t desc = {ZE_STRUCTURE_TYPE_DEVICE_MEM_ALLOC_DESC};
  ze_relaxed_allocation_limits_exp_desc_t relaxedDesc = {
      ZE_STRUCTURE_TYPE_RELAXED_ALLOCATION_LIMITS_EXP_DESC};
  if (relaxed) {
    relaxedDesc.flags = ZE_RELAXED_ALLOCATION_LIMITS_EXP_FLAG_MAX_SIZE;
    desc.pNext = &relaxedDesc;
  }
  return zeMemAllocDevice(c.context, &desc, bytes, 64, c.device, out);
}

// Allocate `bytes` (relaxed), write sentinels across the 4 GiB offset via copy,
// copy back, verify. Returns 0 ok, 1 corrupt, 2 alloc failed.
int sentinel_roundtrip(const Ctx &c, ze_command_list_handle_t cl, std::uint64_t bytes) {
  void *dbuf = nullptr;
  if (try_alloc(c, bytes, true, &dbuf) != ZE_RESULT_SUCCESS) return 2;

  const std::uint64_t G4 = 1ULL << 32;
  std::vector<std::uint64_t> offs;
  for (std::uint64_t o : {std::uint64_t(0), G4 - 8, G4, G4 + 4096, bytes - 8})
    if (o + 8 <= bytes) offs.push_back(o);

  int bad = 0;
  for (auto off : offs) {
    std::uint64_t want = 0xABCD0000ULL + off;  // distinct per offset
    std::uint64_t got = 0;
    // host -> device at off
    zeCommandListAppendMemoryCopy(cl, (char *)dbuf + off, &want, 8, nullptr, 0, nullptr);
    zeCommandListAppendBarrier(cl, nullptr, 0, nullptr);
    // device -> host read back
    zeCommandListAppendMemoryCopy(cl, &got, (char *)dbuf + off, 8, nullptr, 0, nullptr);
    zeCommandListClose(cl);
    ze_command_queue_handle_t q;
    ze_command_queue_desc_t qd = {ZE_STRUCTURE_TYPE_COMMAND_QUEUE_DESC};
    zeCommandQueueCreate(c.context, c.device, &qd, &q);
    zeCommandQueueExecuteCommandLists(q, 1, &cl, nullptr);
    zeCommandQueueSynchronize(q, UINT64_MAX);
    zeCommandQueueDestroy(q);
    zeCommandListReset(cl);
    if (got != want) {
      bad++;
      std::printf("    MISMATCH at offset %.3f GiB: want 0x%llx got 0x%llx\n",
                  double(off) / double(GiB), (unsigned long long)want, (unsigned long long)got);
    }
  }
  zeMemFree(c.context, dbuf);
  return bad ? 1 : 0;
}
}  // namespace

int main() {
  std::printf("arc-a770-lab Level Zero >4GiB allocation probe\n");
  if (zeInit(0) != ZE_RESULT_SUCCESS) {
    std::printf("zeInit failed (no L0 driver). Exiting cleanly.\n");
    return 0;
  }
  Ctx c;
  if (!find_a770(&c)) {
    std::printf("No Arc A770 L0 device found. Exiting cleanly.\n");
    return 0;
  }
  ze_context_desc_t cd = {ZE_STRUCTURE_TYPE_CONTEXT_DESC};
  ZECHECK(zeContextCreate(c.driver, &cd, &c.context), "zeContextCreate");

  // report the device's max alloc
  ze_device_properties_t dp = {ZE_STRUCTURE_TYPE_DEVICE_PROPERTIES};
  zeDeviceGetProperties(c.device, &dp);
  std::printf("maxMemAllocSize = %.2f GiB\n", double(dp.maxMemAllocSize) / double(GiB));

  ze_command_list_desc_t cld = {ZE_STRUCTURE_TYPE_COMMAND_LIST_DESC};
  ze_command_list_handle_t cl;
  ZECHECK(zeCommandListCreate(c.context, c.device, &cld, &cl), "zeCommandListCreate");

  struct { const char *id; double gib; bool relaxed; } alloc_cases[] = {
    {"L0-01 2GiB default",   2.0, false},
    {"L0-02 6GiB default",   6.0, false},
    {"L0-03 6GiB relaxed",   6.0, true},
    {"L0-04 8GiB relaxed",   8.0, true},
  };
  std::printf("\n-- allocation policy --\n");
  for (auto &a : alloc_cases) {
    void *p = nullptr;
    ze_result_t r = try_alloc(c, (std::uint64_t)(a.gib * GiB), a.relaxed, &p);
    std::printf("  %-20s relaxed=%d -> %s (0x%x)\n", a.id, a.relaxed,
                r == ZE_RESULT_SUCCESS ? "ALLOCATED" : "refused", (unsigned)r);
    if (r == ZE_RESULT_SUCCESS) zeMemFree(c.context, p);
  }

  std::printf("\n-- correctness: 6 GiB relaxed, sentinels across 4 GiB offset --\n");
  int rc = sentinel_roundtrip(c, cl, 6 * GiB);
  std::printf("  result: %s\n", rc == 0 ? "ok (values past 4 GiB correct)"
                               : rc == 1 ? "ALLOCATED_BUT_CORRUPT" : "alloc failed");

  zeCommandListDestroy(cl);
  zeContextDestroy(c.context);
  return 0;
}
