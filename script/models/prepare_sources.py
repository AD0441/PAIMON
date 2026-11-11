"""Development-only model conversion. Python is never needed by the app."""
import argparse
import hashlib
import subprocess
import urllib.request
from pathlib import Path

FUNASR = "2b4a0623613013b2b59ae289b189768426006cfa"
LARGE = "6c303ba987b86b93193de93e34bb2b077a6bedc4"
SUPERB = "441a7599c3b22107314dcbd9166621c5c83f2cc5"

def download(url, destination):
    if destination.exists():
        return
    partial = destination.with_suffix(destination.suffix + ".partial")
    try:
        with urllib.request.urlopen(url, timeout=120) as response, partial.open("wb") as output:
            while block := response.read(1024 * 1024):
                output.write(block)
        partial.rename(destination)
    finally:
        partial.unlink(missing_ok=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", choices=["large", "superb"], required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=True)
    repo, revision, files, folder = (
        ("emotion2vec/emotion2vec_plus_large", LARGE, ["config.yaml", "model.pt", "tokens.txt"], "large-source")
        if args.model == "large" else
        ("superb/wav2vec2-base-superb-er", SUPERB, ["config.json", "preprocessor_config.json", "pytorch_model.bin"], "wav-source"))
    source = root / folder
    source.mkdir(exist_ok=True)
    for name in files:
        download(f"https://huggingface.co/{repo}/resolve/{revision}/{name}", source / name)
        with (source / name).open("rb") as handle:
            print(name, hashlib.file_digest(handle, "sha256").hexdigest())
    if args.model == "large":
        upstream = root / "upstream"
        upstream.mkdir(exist_ok=True)
        for name in ["__init__.py", "model.py", "audio.py", "base.py", "modules.py", "fairseq_modules.py", "timm_modules.py", "export_meta.py"]:
            value = subprocess.check_output(["gh", "api", "-H", "Accept: application/vnd.github.raw+json",
                f"repos/modelscope/FunASR/contents/funasr/models/emotion2vec/{name}?ref={FUNASR}"])
            if name == "base.py":
                value = value.replace(b".clamp_min(0)", b".clamp_min(0.0)")
            (upstream / name).write_bytes(value)

if __name__ == "__main__":
    main()
