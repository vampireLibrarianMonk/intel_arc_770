##### Qwen2.5-7B-Instruct | build/llama.cpp/build-vulkan
matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |           pp512 |       983.49 ± 40.84 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |          pp2048 |        832.99 ± 6.97 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |           tg128 |         44.12 ± 0.16 |
##### Qwen2.5-7B-Instruct | build/llama.cpp-coopmat/build-vulkan
matrix cores: KHR_coopmat
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |           pp512 |        113.88 ± 0.49 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |          pp2048 |        111.12 ± 0.10 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |           tg128 |         44.25 ± 0.10 |
##### Meta-Llama-3.1-8B-Instruct | build/llama.cpp/build-vulkan
matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |           pp512 |        977.13 ± 2.07 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |          pp2048 |        783.05 ± 6.52 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |           tg128 |         43.33 ± 0.07 |
##### Meta-Llama-3.1-8B-Instruct | build/llama.cpp-coopmat/build-vulkan
matrix cores: KHR_coopmat
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |           pp512 |         98.73 ± 0.20 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |          pp2048 |         95.66 ± 0.06 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |           tg128 |         43.29 ± 0.38 |
##### Qwen2.5-14B-Instruct | build/llama.cpp/build-vulkan
matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |           pp512 |        522.55 ± 2.50 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |          pp2048 |        415.19 ± 0.64 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |           tg128 |         22.59 ± 0.03 |
##### Qwen2.5-14B-Instruct | build/llama.cpp-coopmat/build-vulkan
matrix cores: KHR_coopmat
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |           pp512 |         51.19 ± 0.12 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |          pp2048 |         49.73 ± 0.06 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |           tg128 |         22.51 ± 0.05 |
##### DONE
