ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(tm) A770 Graphics (DG2) (Intel open-source Mesa driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 32 | shared memory: 65536 | int dot: 1 | matrix cores: none
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| gpt-oss 20B MXFP4 MoE          |  11.27 GiB |    20.91 B | Vulkan     | 999 |           pp512 |      1119.61 ± 17.58 |
| gpt-oss 20B MXFP4 MoE          |  11.27 GiB |    20.91 B | Vulkan     | 999 |           tg128 |         38.74 ± 0.01 |
| gpt-oss 20B MXFP4 MoE          |  11.27 GiB |    20.91 B | Vulkan     | 999 |   pp512 @ d4096 |        757.78 ± 5.30 |
| gpt-oss 20B MXFP4 MoE          |  11.27 GiB |    20.91 B | Vulkan     | 999 |   tg128 @ d4096 |         34.26 ± 0.04 |
| gpt-oss 20B MXFP4 MoE          |  11.27 GiB |    20.91 B | Vulkan     | 999 |  pp512 @ d16384 |        379.59 ± 3.90 |
| gpt-oss 20B MXFP4 MoE          |  11.27 GiB |    20.91 B | Vulkan     | 999 |  tg128 @ d16384 |         25.44 ± 0.01 |

build: b2bb5ab (22)
