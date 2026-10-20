"""Optional local-only MLX worker. No Hub IDs accepted, no automatic downloads."""
import os
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
import sys, json
from pathlib import Path
# Reserve stdout for the JSON protocol even if native libraries print diagnostics.
protocol = os.fdopen(os.dup(sys.stdout.fileno()), "w", buffering=1)
os.dup2(sys.stderr.fileno(), sys.stdout.fileno())
try:
    model_path = Path(sys.argv[1]).expanduser().resolve(strict=True)
    if not (model_path / "config.json").is_file():
        raise ValueError("Select a prepared local MLX model directory")
    import mlx.core as mx
    from mlx_lm import load, generate
    from mlx_lm.sample_utils import make_sampler
    mx.set_cache_limit(128 * 1024 * 1024)
    model, tokenizer = load(str(model_path), tokenizer_config={"trust_remote_code": False})
    for line in sys.stdin:
        request = json.loads(line)
        schema = '{"findings":[{"kind":"topic|overview|idea|decision|task|concept|question|conclusion","text":"...","segmentID":"...","quote":"exact source quote","owner":null,"due":null}]}'
        messages = [
            {"role": "system", "content": request["instructions"] + " Return only valid JSON. Schema: " + schema},
            {"role": "user", "content": json.dumps({k: v for k, v in request.items() if k != "instructions"}, ensure_ascii=False)},
        ]
        prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        if len(tokenizer.encode(prompt)) > 3000:
            raise ValueError("MLX input exceeds bounded 3000 token budget")
        text = generate(model, tokenizer, prompt=prompt, max_tokens=1000,
                        sampler=make_sampler(temp=0), max_kv_size=4096, prefill_step_size=256, verbose=False)
        # No repair that could fabricate content: incomplete JSON is an error.
        result = json.loads(text.strip())
        if not isinstance(result.get("findings"), list):
            raise ValueError("Invalid structured response")
        protocol.write(json.dumps(result, ensure_ascii=False) + "\n")
        protocol.flush()
        mx.clear_cache()
except Exception as error:
    protocol.write(json.dumps({"error": str(error)}) + "\n")
    protocol.flush()
    sys.exit(1)
