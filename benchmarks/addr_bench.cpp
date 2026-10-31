// addr_bench.cpp — H2: performance cost of the stateless >4 GiB addressing path
// vs the stateful/default path on the Arc A770.
//
// Fair comparison: identical workload, identical total element count, identical
// buffer size. The ONLY differences between the two paths are
//   stateful:  kernel built WITHOUT -cl-intel-greater-than-4GB-buffer-required,
//              buffer <= 4 GiB (default allocation)
//   stateless: kernel built WITH that flag, buffer allocated with
//              CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL (can exceed 4 GiB)
//
// To isolate addressing cost from allocation size, the DEFAULT size is 3.5 GiB so
// BOTH paths can hold it in a single buffer. Pass --size-gib N to change it; a size
// > 4 runs only the stateless path (stateful cannot allocate it) and is labelled so.
//
// Protocol (STRATEGY §5): warmup 5, measured 20, report median + p95, kernel time
// only (clEvent profiling), host<->device excluded. No fabricated numbers.

#define CL_TARGET_OPENCL_VERSION 300
#define CL_USE_DEPRECATED_OPENCL_1_2_APIS
#include <CL/cl.h>
#ifdef __has_include
#  if __has_include(<CL/cl_ext.h>)
#    include <CL/cl_ext.h>
#  endif
#endif

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#ifndef CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL
#  define CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL (1ULL << 23)
#endif

namespace {
constexpr std::uint64_t GiB = 1ULL << 30;
constexpr std::uint64_t kElem = sizeof(cl_ulong);

cl_device_id find_a770(std::string *name) {
  cl_uint np = 0;
  if (clGetPlatformIDs(0, nullptr, &np) != CL_SUCCESS || np == 0) return nullptr;
  std::vector<cl_platform_id> ps(np); clGetPlatformIDs(np, ps.data(), nullptr);
  for (auto p : ps) {
    cl_uint nd = 0;
    if (clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 0, nullptr, &nd) != CL_SUCCESS || !nd) continue;
    std::vector<cl_device_id> ds(nd); clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, nd, ds.data(), nullptr);
    for (auto d : ds) {
      char n[256] = {0}; clGetDeviceInfo(d, CL_DEVICE_NAME, sizeof(n), n, nullptr);
      std::string s(n);
      if (s.find("A770") != std::string::npos || s.find("Arc") != std::string::npos) {
        if (name) *name = s; return d;
      }
    }
  }
  return nullptr;
}

std::string load(const std::string &p) { std::ifstream f(p); std::stringstream s; s << f.rdbuf(); return s.str(); }

double median(std::vector<double> v) {
  std::sort(v.begin(), v.end());
  size_t n = v.size();
  return n ? (n % 2 ? v[n/2] : (v[n/2-1]+v[n/2])/2.0) : 0.0;
}
double pct(std::vector<double> v, double p) {
  std::sort(v.begin(), v.end());
  if (v.empty()) return 0.0;
  size_t i = (size_t)(p/100.0*(v.size()-1) + 0.5);
  return v[std::min(i, v.size()-1)];
}

cl_program build(cl_context c, cl_device_id d, const std::string &src, bool stateless) {
  const char *s = src.c_str(); size_t len = src.size();
  cl_program pr = clCreateProgramWithSource(c, 1, &s, &len, nullptr);
  const char *opt = stateless ? "-cl-std=CL2.0 -cl-intel-greater-than-4GB-buffer-required"
                              : "-cl-std=CL2.0";
  if (clBuildProgram(pr, 1, &d, opt, nullptr, nullptr) != CL_SUCCESS) return nullptr;
  return pr;
}

cl_mem make_buf(cl_context c, bool relaxed, std::uint64_t bytes, cl_int *err) {
  cl_mem_flags f = CL_MEM_READ_WRITE;
  if (relaxed) f |= CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL;
  return clCreateBuffer(c, f, bytes, nullptr, err);
}

// Time one kernel over reps, return kernel ms samples via clEvent profiling.
std::vector<double> time_kernel(cl_command_queue q, cl_kernel k, std::uint64_t n,
                                int warmup, int reps) {
  size_t gws = (size_t)n;
  for (int i = 0; i < warmup; ++i) clEnqueueNDRangeKernel(q, k, 1, nullptr, &gws, nullptr, 0, nullptr, nullptr);
  clFinish(q);
  std::vector<double> ms;
  for (int i = 0; i < reps; ++i) {
    cl_event e;
    clEnqueueNDRangeKernel(q, k, 1, nullptr, &gws, nullptr, 0, nullptr, &e);
    clWaitForEvents(1, &e);
    cl_ulong t0 = 0, t1 = 0;
    clGetEventProfilingInfo(e, CL_PROFILING_COMMAND_START, sizeof(t0), &t0, nullptr);
    clGetEventProfilingInfo(e, CL_PROFILING_COMMAND_END, sizeof(t1), &t1, nullptr);
    ms.push_back(double(t1 - t0) / 1e6);
    clReleaseEvent(e);
  }
  return ms;
}

struct Row { std::string workload, path; double med_ms, p95_ms; std::uint64_t n; bool ran; };

void run_path(cl_context ctx, cl_command_queue q, cl_device_id dev, const std::string &src,
              bool stateless, std::uint64_t n, int warmup, int reps, std::vector<Row> &rows) {
  const char *label = stateless ? "stateless" : "stateful";
  std::uint64_t bytes = n * kElem;
  cl_program pr = build(ctx, dev, src, stateless);
  if (!pr) { std::printf("  [%s] build failed\n", label); return; }
  cl_int e = 0;
  cl_mem a = make_buf(ctx, stateless, bytes, &e);
  if (e != CL_SUCCESS) { std::printf("  [%s] alloc failed (%d)\n", label, e); clReleaseProgram(pr); return; }
  cl_mem b = make_buf(ctx, stateless, bytes, &e);
  if (e != CL_SUCCESS) { std::printf("  [%s] alloc(b) failed (%d)\n", label, e); clReleaseMemObject(a); clReleaseProgram(pr); return; }
  cl_ulong cn = n;

  struct { const char *kn, *wl; bool two; } ks[] = {
    {"w_addr", "W1_addr", false}, {"w_stream", "W2_stream", true}, {"w_random", "W3_random", true},
  };
  for (auto &kk : ks) {
    cl_kernel k = clCreateKernel(pr, kk.kn, nullptr);
    if (!kk.two) { clSetKernelArg(k, 0, sizeof(cl_mem), &a); clSetKernelArg(k, 1, sizeof(cl_ulong), &cn); }
    else { clSetKernelArg(k, 0, sizeof(cl_mem), &a); clSetKernelArg(k, 1, sizeof(cl_mem), &b); clSetKernelArg(k, 2, sizeof(cl_ulong), &cn); }
    auto ms = time_kernel(q, k, n, warmup, reps);
    Row r{kk.wl, label, median(ms), pct(ms, 95), n, true};
    rows.push_back(r);
    std::printf("  %-10s %-10s med=%8.3f ms  p95=%8.3f ms\n", r.workload.c_str(), label, r.med_ms, r.p95_ms);
    clReleaseKernel(k);
  }
  clReleaseMemObject(a); clReleaseMemObject(b); clReleaseProgram(pr);
}
}  // namespace

int main(int argc, char **argv) {
  double size_gib = 3.5; std::string json, kernel = "workloads/addr_bench.cl";
  int warmup = 5, reps = 20;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--size-gib" && i+1 < argc) size_gib = atof(argv[++i]);
    else if (a == "--json" && i+1 < argc) json = argv[++i];
    else if (a == "--kernel" && i+1 < argc) kernel = argv[++i];
    else if (a == "--reps" && i+1 < argc) reps = atoi(argv[++i]);
  }
  std::printf("arc-a770-lab H2 addressing benchmark  size=%.2f GiB reps=%d\n", size_gib, reps);

  std::string name; cl_device_id dev = find_a770(&name);
  if (!dev) { std::printf("No A770 found; exiting cleanly.\n"); return 0; }
  std::printf("Device: %s\n", name.c_str());

  std::string src = load(kernel);
  if (src.empty()) { std::printf("ERROR: no kernel at %s\n", kernel.c_str()); return 2; }

  cl_int e = 0;
  cl_context ctx = clCreateContext(nullptr, 1, &dev, nullptr, nullptr, &e);
  cl_queue_properties props[] = {CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE, 0};
  cl_command_queue q = clCreateCommandQueueWithProperties(ctx, dev, props, &e);

  std::uint64_t n = (std::uint64_t)(size_gib * GiB) / kElem;
  std::vector<Row> rows;

  std::printf("\n-- stateful path (default, buffer must be <= 4 GiB) --\n");
  if (size_gib <= 4.0) run_path(ctx, q, dev, src, false, n, warmup, reps, rows);
  else std::printf("  skipped: %.2f GiB exceeds the 4 GiB stateful cap\n", size_gib);

  std::printf("-- stateless path (relaxed alloc + >4GB build flag) --\n");
  run_path(ctx, q, dev, src, true, n, warmup, reps, rows);

  // Penalty summary (stateless vs stateful) for matching workloads.
  std::printf("\n-- stateless penalty (med) --\n");
  for (auto &sf : rows) if (sf.path == "stateful")
    for (auto &sl : rows) if (sl.path == "stateless" && sl.workload == sf.workload)
      std::printf("  %-10s  x%.3f\n", sf.workload.c_str(), sl.med_ms / sf.med_ms);

  if (!json.empty()) {
    std::ofstream o(json);
    o << "{\n  \"device\":\"" << name << "\",\n  \"size_GiB\":" << size_gib
      << ",\n  \"reps\":" << reps << ",\n  \"rows\":[\n";
    for (size_t i = 0; i < rows.size(); ++i) {
      auto &r = rows[i];
      o << "    {\"workload\":\"" << r.workload << "\",\"path\":\"" << r.path
        << "\",\"n_elem\":" << r.n << ",\"med_ms\":" << r.med_ms << ",\"p95_ms\":" << r.p95_ms << "}"
        << (i+1<rows.size()?",":"") << "\n";
    }
    o << "  ]\n}\n";
    std::printf("\nwrote %s\n", json.c_str());
  }
  clReleaseCommandQueue(q); clReleaseContext(ctx);
  return 0;
}
