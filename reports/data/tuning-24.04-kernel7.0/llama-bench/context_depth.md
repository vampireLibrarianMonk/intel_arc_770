##### Qwen2.5-7B-Instruct
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |           pp512 |        996.83 ± 9.29 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |            tg64 |         44.57 ± 0.73 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   pp512 @ d4096 |        487.97 ± 6.27 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |    tg64 @ d4096 |         38.37 ± 0.09 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |  pp512 @ d16384 |        144.36 ± 0.66 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |   tg64 @ d16384 |         27.80 ± 0.15 |
##### Meta-Llama-3.1-8B-Instruct
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |           pp512 |       983.06 ± 37.94 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |            tg64 |         42.95 ± 0.37 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   pp512 @ d4096 |       388.42 ± 20.38 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |    tg64 @ d4096 |         39.36 ± 0.16 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |  pp512 @ d16384 |         97.90 ± 2.49 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |   tg64 @ d16384 |         31.68 ± 0.09 |
##### Qwen2.5-14B-Instruct
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |           pp512 |        521.07 ± 3.62 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |            tg64 |         22.47 ± 0.07 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   pp512 @ d4096 |        196.79 ± 3.68 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |    tg64 @ d4096 |         17.96 ± 0.10 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |  pp512 @ d16384 |         57.56 ± 0.29 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |   tg64 @ d16384 |         11.42 ± 0.01 |
##### DeepSeek-Coder-V2-Lite-Instruct
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |           pp512 |       1435.56 ± 4.56 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |            tg64 |         63.56 ± 1.65 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   pp512 @ d4096 |       537.82 ± 41.42 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |    tg64 @ d4096 |         50.48 ± 0.71 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |  pp512 @ d16384 |        177.82 ± 4.81 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |   tg64 @ d16384 |         31.03 ± 0.08 |
##### DONE
