// large_buffer.cpp — Arc A770 >4 GiB OpenCL correctness harness.
//
// Runs the MEM-01..MEM-10 matrix from docs/STRATEGY.md on a real A770:
//   * selects the A770 explicitly (by name), never "first device"
//   * regular vs relaxed allocation (CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL)
//   * kernels built with/without -cl-intel-greater-than-4GB-buffer-required
//   * writes 64-bit sentinels across the 4 GiB byte offset, verifies vs the CPU oracle
//   * captures the EXACT cl error code (e.g. CL_INVALID_BUFFER_SIZE -61) — never
//     collapses a policy rejection and a real OOM into one bucket
//   * allocation success is NEVER treated as proof of correctness
//
// With no device present it prints the plan and exits 0 (no fabricated results).
// Build: see CMakeLists.txt in this directory.  Emits JSON to --json <path> if given.

#define CL_TARGET_OPENCL_VERSION 300
#define CL_USE_DEPRECATED_OPENCL_1_2_APIS

#include <CL/cl.h>
#ifdef __has_include
#  if __has_include(<CL/cl_ext.h>)
#    include <CL/cl_ext.h>
#  endif
#endif

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "../oracles/sentinel_oracle.hpp"

// Intel extension bits — define defensively in case the headers predate them.
#ifndef CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL
#  define CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL (1ULL << 23)
#endif

namespace {

constexpr std::uint64_t kDefaultSeed = 123456ULL;
constexpr std::uint64_t GiB = 1ULL << 30;
constexpr std::uint64_t kElem = sizeof(cl_ulong);  // 8 bytes

struct Case {
  std::string id;
  std::uint64_t bytes;
  bool relaxed_allocation;    // CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL
  bool stateless_compile;     // -cl-intel-greater-than-4GB-buffer-required
  const char *expectation;
};

std::vector<Case> build_matrix() {
  return {
      {"MEM-01", 256 * (1ULL << 20), false, false, "run; standard rw + checksum"},
      {"MEM-02", 2 * GiB,            false, false, "run; checksum/throughput"},
      {"MEM-03", 4 * GiB - (1ULL << 20), false, false, "near max; correct behavior"},
      {"MEM-04", 4 * GiB + (1ULL << 20), false, false, "expect policy reject if still limited"},
      {"MEM-05", 6 * GiB,            true,  true,  "supported >4GiB path; verify past 4GiB"},
      {"MEM-06", 8 * GiB,            true,  true,  "supported; strided/random rw"},
      {"MEM-09", 6 * GiB,            true,  false, "NEGATIVE: relaxed alloc only; detect corruption"},
      {"MEM-10", 6 * GiB,            false, true,  "NEGATIVE: stateless only; incomplete"},
  };
}

const char *cl_err_name(cl_int e) {
  switch (e) {
    case CL_SUCCESS: return "CL_SUCCESS";
    case CL_INVALID_BUFFER_SIZE: return "CL_INVALID_BUFFER_SIZE";
    case CL_MEM_OBJECT_ALLOCATION_FAILURE: return "CL_MEM_OBJECT_ALLOCATION_FAILURE";
    case CL_OUT_OF_RESOURCES: return "CL_OUT_OF_RESOURCES";
    case CL_OUT_OF_HOST_MEMORY: return "CL_OUT_OF_HOST_MEMORY";
    case CL_INVALID_VALUE: return "CL_INVALID_VALUE";
    case CL_BUILD_PROGRAM_FAILURE: return "CL_BUILD_PROGRAM_FAILURE";
    default: return "CL_ERROR";
  }
}

cl_device_id find_a770(cl_platform_id *plat_out, std::string *name_out) {
  cl_uint np = 0;
  if (clGetPlatformIDs(0, nullptr, &np) != CL_SUCCESS || np == 0) return nullptr;
  std::vector<cl_platform_id> plats(np);
  clGetPlatformIDs(np, plats.data(), nullptr);
  for (cl_platform_id p : plats) {
    cl_uint nd = 0;
    if (clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 0, nullptr, &nd) != CL_SUCCESS || nd == 0) continue;
    std::vector<cl_device_id> devs(nd);
    clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, nd, devs.data(), nullptr);
    for (cl_device_id d : devs) {
      char name[256] = {0};
      clGetDeviceInfo(d, CL_DEVICE_NAME, sizeof(name), name, nullptr);
      std::string n(name);
      if (n.find("A770") != std::string::npos || n.find("Arc") != std::string::npos) {
        if (plat_out) *plat_out = p;
        if (name_out) *name_out = n;
        return d;
      }
    }
  }
  return nullptr;
}

std::string load_file(const std::string &path) {
  std::ifstream f(path);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

struct Result {
  std::string id;
  double size_gib;
  bool relaxed, stateless;
  bool build_ok = false;
  bool allocated = false;
  cl_int alloc_err = CL_SUCCESS;
  bool sentinels_ok = false;
  std::uint64_t device_mismatches = 0;  // from sentinel_check kernel
  std::uint64_t host_mismatches = 0;     // host read-back cross-check
  std::string verdict;
};

// Build the program with or without the stateless flag; report the exact outcome.
cl_program build_program(cl_context ctx, cl_device_id dev, const std::string &src,
                         bool stateless, cl_int *err_out, std::string *log_out) {
  const char *s = src.c_str();
  size_t len = src.size();
  cl_int err = CL_SUCCESS;
  cl_program prog = clCreateProgramWithSource(ctx, 1, &s, &len, &err);
  if (err != CL_SUCCESS) { *err_out = err; return nullptr; }
  const char *opts = stateless ? "-cl-std=CL2.0 -cl-intel-greater-than-4GB-buffer-required"
                               : "-cl-std=CL2.0";
  err = clBuildProgram(prog, 1, &dev, opts, nullptr, nullptr);
  *err_out = err;
  if (err != CL_SUCCESS && log_out) {
    size_t lg = 0;
    clGetProgramBuildInfo(prog, dev, CL_PROGRAM_BUILD_LOG, 0, nullptr, &lg);
    std::string log(lg, '\0');
    clGetProgramBuildInfo(prog, dev, CL_PROGRAM_BUILD_LOG, lg, log.data(), nullptr);
    *log_out = log;
  }
  return prog;
}

Result run_case(cl_context ctx, cl_command_queue q, cl_device_id dev,
                const std::string &src, const Case &c) {
  Result r{c.id, double(c.bytes) / double(GiB), c.relaxed_allocation, c.stateless_compile, {}};
  const std::uint64_t n_elems = c.bytes / kElem;

  cl_int berr = CL_SUCCESS;
  std::string blog;
  cl_program prog = build_program(ctx, dev, src, c.stateless_compile, &berr, &blog);
  r.build_ok = (berr == CL_SUCCESS);
  if (!r.build_ok) {
    r.verdict = std::string("build_failed:") + cl_err_name(berr);
    if (prog) clReleaseProgram(prog);
    return r;
  }

  // Allocate — this is where the 4 GiB policy shows up. Capture the exact code.
  cl_mem_flags flags = CL_MEM_READ_WRITE;
  cl_mem buf = nullptr;
  cl_int aerr = CL_SUCCESS;
#ifdef CL_MEM_FLAGS_INTEL
  if (c.relaxed_allocation) {
    cl_mem_properties_intel props[] = {
        CL_MEM_FLAGS_INTEL, CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL, 0};
    buf = clCreateBufferWithPropertiesINTEL(ctx, props, flags, c.bytes, nullptr, &aerr);
  } else
#endif
  {
    if (c.relaxed_allocation) flags |= CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL;
    buf = clCreateBuffer(ctx, flags, c.bytes, nullptr, &aerr);
  }
  r.alloc_err = aerr;
  r.allocated = (aerr == CL_SUCCESS && buf != nullptr);
  if (!r.allocated) {
    r.verdict = std::string("alloc_rejected:") + cl_err_name(aerr);
    clReleaseProgram(prog);
    return r;
  }

  // Write sentinels across the whole buffer (64-bit global size).
  cl_kernel kw = clCreateKernel(prog, "sentinel_write", nullptr);
  cl_ulong seed = kDefaultSeed, ne = n_elems;
  clSetKernelArg(kw, 0, sizeof(cl_mem), &buf);
  clSetKernelArg(kw, 1, sizeof(cl_ulong), &seed);
  clSetKernelArg(kw, 2, sizeof(cl_ulong), &ne);
  size_t gws = (size_t)n_elems;
  cl_int kerr = clEnqueueNDRangeKernel(q, kw, 1, nullptr, &gws, nullptr, 0, nullptr, nullptr);
  clFinish(q);

  // Device-side sparse check across the 4 GiB offset.
  auto offs = arc_oracle::sentinel_byte_offsets(c.bytes, kElem);
  std::vector<cl_ulong> idx;
  for (auto off : offs) idx.push_back(off / kElem);
  cl_mem idx_buf = clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
                                  idx.size() * sizeof(cl_ulong), idx.data(), nullptr);
  cl_ulong mism = 0;
  cl_mem mism_buf = clCreateBuffer(ctx, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR,
                                   sizeof(cl_ulong), &mism, nullptr);
  cl_kernel kc = clCreateKernel(prog, "sentinel_check", nullptr);
  cl_ulong n_idx = idx.size();
  clSetKernelArg(kc, 0, sizeof(cl_mem), &buf);
  clSetKernelArg(kc, 1, sizeof(cl_mem), &idx_buf);
  clSetKernelArg(kc, 2, sizeof(cl_ulong), &n_idx);
  clSetKernelArg(kc, 3, sizeof(cl_ulong), &seed);
  clSetKernelArg(kc, 4, sizeof(cl_mem), &mism_buf);
  size_t gws2 = idx.size();
  clEnqueueNDRangeKernel(q, kc, 1, nullptr, &gws2, nullptr, 0, nullptr, nullptr);
  clEnqueueReadBuffer(q, mism_buf, CL_TRUE, 0, sizeof(cl_ulong), &mism, 0, nullptr, nullptr);
  clFinish(q);
  r.device_mismatches = mism;

  // Independent host read-back at each sentinel index vs the CPU oracle.
  for (auto off : offs) {
    std::uint64_t i = off / kElem;
    cl_ulong got = 0;
    clEnqueueReadBuffer(q, buf, CL_TRUE, off, sizeof(cl_ulong), &got, 0, nullptr, nullptr);
    if (got != arc_oracle::expected_value(seed, i)) r.host_mismatches++;
  }

  r.sentinels_ok = (kerr == CL_SUCCESS && r.device_mismatches == 0 && r.host_mismatches == 0);
  r.verdict = r.sentinels_ok ? "ok"
              : (r.allocated ? "ALLOCATED_BUT_CORRUPT" : "fail");

  clReleaseKernel(kw);
  clReleaseKernel(kc);
  clReleaseMemObject(idx_buf);
  clReleaseMemObject(mism_buf);
  clReleaseMemObject(buf);
  clReleaseProgram(prog);
  return r;
}

void print_plan() {
  std::printf("Planned correctness matrix (no device => plan only):\n");
  for (const Case &c : build_matrix())
    std::printf("  %-7s  %6.2f GiB  relaxed=%d stateless=%d  :: %s\n", c.id.c_str(),
                double(c.bytes) / double(GiB), c.relaxed_allocation, c.stateless_compile,
                c.expectation);
}

}  // namespace

int main(int argc, char **argv) {
  std::string json_path;
  std::string kernel_path = "kernels/sentinel.cl";
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--json" && i + 1 < argc) json_path = argv[++i];
    else if (a == "--kernel" && i + 1 < argc) kernel_path = argv[++i];
  }

  std::printf("arc-a770-lab OpenCL >4GiB correctness harness\n");

  cl_platform_id plat = nullptr;
  std::string dev_name;
  cl_device_id dev = find_a770(&plat, &dev_name);
  if (dev == nullptr) {
    std::printf("No Arc A770 OpenCL device found.\n");
    print_plan();
    std::printf("Exiting cleanly: no device => no measurements (by design).\n");
    return 0;
  }
  std::printf("Device: %s\n", dev_name.c_str());

  cl_ulong max_alloc = 0, gmem = 0;
  clGetDeviceInfo(dev, CL_DEVICE_MAX_MEM_ALLOC_SIZE, sizeof(max_alloc), &max_alloc, nullptr);
  clGetDeviceInfo(dev, CL_DEVICE_GLOBAL_MEM_SIZE, sizeof(gmem), &gmem, nullptr);
  std::printf("CL_DEVICE_GLOBAL_MEM_SIZE    = %.2f GiB\n", double(gmem) / double(GiB));
  std::printf("CL_DEVICE_MAX_MEM_ALLOC_SIZE = %.2f GiB\n", double(max_alloc) / double(GiB));

  std::string src = load_file(kernel_path);
  if (src.empty()) {
    std::printf("ERROR: could not read kernel source at %s\n", kernel_path.c_str());
    return 2;
  }

  cl_int err = CL_SUCCESS;
  cl_context ctx = clCreateContext(nullptr, 1, &dev, nullptr, nullptr, &err);
  cl_command_queue q = clCreateCommandQueueWithProperties(ctx, dev, nullptr, &err);

  std::vector<Result> results;
  std::printf("\n%-7s %8s %7s %9s %-24s\n", "case", "size", "relaxed", "statel.", "verdict");
  for (const Case &c : build_matrix()) {
    Result r = run_case(ctx, q, dev, src, c);
    results.push_back(r);
    std::printf("%-7s %6.2fG %7d %9d %-24s (alloc_err=%s dev_mis=%llu host_mis=%llu)\n",
                r.id.c_str(), r.size_gib, r.relaxed, r.stateless, r.verdict.c_str(),
                cl_err_name(r.alloc_err),
                (unsigned long long)r.device_mismatches, (unsigned long long)r.host_mismatches);
  }

  if (!json_path.empty()) {
    std::ofstream o(json_path);
    o << "{\n  \"device\": \"" << dev_name << "\",\n";
    o << "  \"global_mem_GiB\": " << double(gmem) / double(GiB) << ",\n";
    o << "  \"max_alloc_GiB\": " << double(max_alloc) / double(GiB) << ",\n";
    o << "  \"cases\": [\n";
    for (size_t i = 0; i < results.size(); ++i) {
      const Result &r = results[i];
      o << "    {\"id\":\"" << r.id << "\",\"size_GiB\":" << r.size_gib
        << ",\"relaxed\":" << (r.relaxed ? "true" : "false")
        << ",\"stateless\":" << (r.stateless ? "true" : "false")
        << ",\"build_ok\":" << (r.build_ok ? "true" : "false")
        << ",\"allocated\":" << (r.allocated ? "true" : "false")
        << ",\"alloc_err\":\"" << cl_err_name(r.alloc_err) << "\""
        << ",\"device_mismatches\":" << r.device_mismatches
        << ",\"host_mismatches\":" << r.host_mismatches
        << ",\"sentinels_ok\":" << (r.sentinels_ok ? "true" : "false")
        << ",\"verdict\":\"" << r.verdict << "\"}" << (i + 1 < results.size() ? "," : "") << "\n";
    }
    o << "  ]\n}\n";
    std::printf("\nwrote %s\n", json_path.c_str());
  }

  clReleaseCommandQueue(q);
  clReleaseContext(ctx);
  return 0;
}
