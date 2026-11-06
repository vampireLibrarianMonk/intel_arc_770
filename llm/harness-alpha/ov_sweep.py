# Quick OpenVINO GenAI config sweep on one model. Greedy, fixed prompts, reports TPOT-derived tok/s.
import sys, time, json, openvino_genai as og
model, dev = sys.argv[1], "GPU"
prompts=["Write a Python function that reverses a string.",
         "Write a short, vivid paragraph about a lighthouse keeper during a storm."]
configs={
 "default": {},
 "kv_f16": {"KV_CACHE_PRECISION":"f16"},
 "kv_u8": {"KV_CACHE_PRECISION":"u8"},
 "dq32": {"DYNAMIC_QUANTIZATION_GROUP_SIZE":"32"},
 "latency": {"PERFORMANCE_HINT":"LATENCY"},
}
only=sys.argv[2:] or list(configs)
for name in only:
    props=configs[name]
    try:
        t=time.time(); p=og.LLMPipeline(model,dev,**props); load=time.time()-t
    except Exception as e:
        print(json.dumps({"cfg":name,"error":str(e)[:300]}),flush=True); continue
    cfg=og.GenerationConfig(); cfg.max_new_tokens=256; cfg.do_sample=False
    p.generate(["hi"],cfg)  # warm-up
    tps=[];ttft=[]
    for pr in prompts:
        r=p.generate([pr],cfg); pm=r.perf_metrics
        tps.append(1000/pm.get_tpot().mean); ttft.append(pm.get_ttft().mean)
    print(json.dumps({"cfg":name,"load_s":round(load,1),"tok_s":[round(x,1) for x in tps],"ttft_ms":[round(x) for x in ttft]}),flush=True)
    del p
