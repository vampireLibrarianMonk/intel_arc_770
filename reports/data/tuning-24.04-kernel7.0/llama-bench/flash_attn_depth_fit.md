##### Qwen2.5-7B fa on/off at depth
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   0 |           pp512 |        971.23 ± 6.96 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   0 |            tg64 |         45.74 ± 0.57 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   0 |   pp512 @ d4096 |       656.30 ± 10.30 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   0 |    tg64 @ d4096 |         41.56 ± 2.56 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   0 |  pp512 @ d16384 |        292.90 ± 8.07 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   0 |   tg64 @ d16384 |         36.15 ± 0.12 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   1 |           pp512 |        999.16 ± 8.93 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   1 |            tg64 |         43.87 ± 0.24 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   1 |   pp512 @ d4096 |       442.51 ± 51.85 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   1 |    tg64 @ d4096 |         38.35 ± 0.13 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   1 |  pp512 @ d16384 |        141.71 ± 1.29 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   1 |   tg64 @ d16384 |         27.80 ± 0.10 |
##### Qwen2.5-7B fa on + q8_0 KV at depth
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   q8_0 |   q8_0 |   1 |   pp512 @ d4096 |       460.77 ± 22.67 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   q8_0 |   q8_0 |   1 |    tg64 @ d4096 |         36.46 ± 0.13 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   q8_0 |   q8_0 |   1 |  pp512 @ d16384 |        163.36 ± 4.07 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   q8_0 |   q8_0 |   1 |   tg64 @ d16384 |         26.15 ± 0.16 |
##### DONE
##### Meta-Llama-3.1-8B-Instruct fa off/on at depth
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   0 |   pp512 @ d4096 |       604.92 ± 29.04 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   0 |    tg64 @ d4096 |         38.31 ± 0.22 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   0 |  pp512 @ d16384 |        245.22 ± 0.22 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   0 |   tg64 @ d16384 |         30.27 ± 0.04 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   1 |   pp512 @ d4096 |       369.66 ± 16.02 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   1 |    tg64 @ d4096 |         39.25 ± 0.33 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   1 |  pp512 @ d16384 |        100.44 ± 0.95 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   1 |   tg64 @ d16384 |         31.46 ± 0.35 |
##### Qwen2.5-14B-Instruct fa off/on at depth
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   0 |   pp512 @ d4096 |        320.53 ± 5.98 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   0 |    tg64 @ d4096 |         21.29 ± 0.04 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   0 |  pp512 @ d16384 |        131.68 ± 0.04 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   0 |   tg64 @ d16384 |         17.21 ± 0.02 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   1 |   pp512 @ d4096 |        199.12 ± 1.08 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   1 |    tg64 @ d4096 |         17.98 ± 0.05 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   1 |  pp512 @ d16384 |         58.04 ± 0.05 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   1 |   tg64 @ d16384 |         11.41 ± 0.02 |
##### DeepSeek-Coder-V2-Lite-Instruct fa off/on at depth
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   0 |   pp512 @ d4096 |       951.02 ± 52.64 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   0 |    tg64 @ d4096 |         50.32 ± 0.91 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   0 |  pp512 @ d16384 |        440.73 ± 3.98 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   0 |   tg64 @ d16384 |         30.42 ± 1.49 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   1 |   pp512 @ d4096 |       556.35 ± 50.07 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   1 |    tg64 @ d4096 |         50.64 ± 0.74 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   1 |  pp512 @ d16384 |        181.99 ± 0.30 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   1 |   tg64 @ d16384 |         31.03 ± 0.17 |
##### 7B fa off, deeper (fit check)
error: invalid parameter for argument: -c
##### 14B fa off, deeper (fit check)
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
ggml_vulkan: Device memory allocation of size 2055208960 failed.
ggml_vulkan: vk::Device::allocateMemory: ErrorOutOfDeviceMemory
ggml_gallocr_reserve_n_impl: failed to allocate Vulkan0 buffer of size 4212142080
graph_reserve: failed to allocate compute buffers
llama_init_from_model: failed to initialize the context: failed to allocate compute pp buffers
llama_bench: error: failed to create context with model 'models/Qwen2.5-14B-Instruct-Q4_K_M.gguf'
##### DONE
##### Qwen2.5-7B-Instruct fa=0 depth=32768
| qwen2 7B Q4_K - Medium | 4.36 GiB | 7.62 B | 0 | pp512 @ d32768 | 173.85 ± 0.00 |
| qwen2 7B Q4_K - Medium | 4.36 GiB | 7.62 B | 0 | tg32 @ d32768 | 29.96 ± 0.00 |
##### Qwen2.5-7B-Instruct fa=1 depth=32768
| qwen2 7B Q4_K - Medium | 4.36 GiB | 7.62 B | 1 | pp512 @ d32768 | 64.28 ± 0.00 |
| qwen2 7B Q4_K - Medium | 4.36 GiB | 7.62 B | 1 | tg32 @ d32768 | 19.77 ± 0.00 |
##### Qwen2.5-14B-Instruct fa=1 depth=24576
| qwen2 14B Q4_K - Medium | 8.37 GiB | 14.77 B | 1 | pp512 @ d24576 | 36.29 ± 0.00 |
| qwen2 14B Q4_K - Medium | 8.37 GiB | 14.77 B | 1 | tg32 @ d24576 | 8.75 ± 0.00 |
##### Qwen2.5-14B-Instruct fa=0 depth=20480
| qwen2 14B Q4_K - Medium | 8.37 GiB | 14.77 B | 0 | pp512 @ d20480 | 110.90 ± 0.00 |
| qwen2 14B Q4_K - Medium | 8.37 GiB | 14.77 B | 0 | tg32 @ d20480 | 15.74 ± 0.00 |
##### DONE
