##### Phi-3.5-mini-instruct
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(tm) A770 Graphics (DG2) (Intel open-source Mesa driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 32 | shared memory: 65536 | int dot: 1 | matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| phi3 3B Q4_K - Medium          |   2.23 GiB |     3.82 B | Vulkan     | 999 |           pp512 |      1463.45 ± 44.50 |
| phi3 3B Q4_K - Medium          |   2.23 GiB |     3.82 B | Vulkan     | 999 |           tg128 |         77.58 ± 0.39 |
build: b2bb5ab (22)
##### Qwen2.5-7B-Instruct
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(tm) A770 Graphics (DG2) (Intel open-source Mesa driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 32 | shared memory: 65536 | int dot: 1 | matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |           pp512 |       966.76 ± 35.11 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | Vulkan     | 999 |           tg128 |         43.64 ± 0.02 |
build: b2bb5ab (22)
##### Meta-Llama-3.1-8B-Instruct
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(tm) A770 Graphics (DG2) (Intel open-source Mesa driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 32 | shared memory: 65536 | int dot: 1 | matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |           pp512 |       964.48 ± 17.68 |
| llama 8B Q4_K - Medium         |   4.58 GiB |     8.03 B | Vulkan     | 999 |           tg128 |         42.64 ± 0.18 |
build: b2bb5ab (22)
##### gemma-2-9b-it
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(tm) A770 Graphics (DG2) (Intel open-source Mesa driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 32 | shared memory: 65536 | int dot: 1 | matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| gemma2 9B Q4_K - Medium        |   5.36 GiB |     9.24 B | Vulkan     | 999 |           pp512 |       711.50 ± 24.32 |
| gemma2 9B Q4_K - Medium        |   5.36 GiB |     9.24 B | Vulkan     | 999 |           tg128 |         27.40 ± 0.06 |
build: b2bb5ab (22)
##### Mistral-Nemo-Instruct-2407
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(tm) A770 Graphics (DG2) (Intel open-source Mesa driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 32 | shared memory: 65536 | int dot: 1 | matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| llama 13B Q4_K - Medium        |   6.96 GiB |    12.25 B | Vulkan     | 999 |           pp512 |       641.39 ± 18.11 |
| llama 13B Q4_K - Medium        |   6.96 GiB |    12.25 B | Vulkan     | 999 |           tg128 |         27.69 ± 0.13 |
build: b2bb5ab (22)
##### Qwen2.5-14B-Instruct
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(tm) A770 Graphics (DG2) (Intel open-source Mesa driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 32 | shared memory: 65536 | int dot: 1 | matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |           pp512 |       528.97 ± 14.95 |
| qwen2 14B Q4_K - Medium        |   8.37 GiB |    14.77 B | Vulkan     | 999 |           tg128 |         22.68 ± 0.16 |
build: b2bb5ab (22)
##### DeepSeek-Coder-V2-Lite-Instruct
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(tm) A770 Graphics (DG2) (Intel open-source Mesa driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 32 | shared memory: 65536 | int dot: 1 | matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |           pp512 |      1414.35 ± 70.28 |
| deepseek2 16B Q4_K - Medium    |   9.65 GiB |    15.71 B | Vulkan     | 999 |           tg128 |         63.52 ± 0.03 |
build: b2bb5ab (22)
##### DONE
