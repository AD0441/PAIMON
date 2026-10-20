#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHON="${LAI_PYTHON:-python3}"
"$PYTHON" -c 'import sys; assert sys.version_info >= (3,11), "Use Python 3.11+ via LAI_PYTHON"'
"$PYTHON" -m venv Integrations/.venv
Integrations/.venv/bin/python -m pip install 'mlx-lm==0.31.3' 'huggingface-hub>=0.34,<2'
Integrations/.venv/bin/python -m pip freeze > Integrations/mlx-resolved.txt
printf '%s\n' 'MLX installed. No model downloaded. Use an explicitly prepared local Qwen2.5-1.5B-Instruct-4bit directory.'
