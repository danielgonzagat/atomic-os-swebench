#!/bin/bash
# 3 DeepSeek paralelos na MESMA tarefa (pylint-7277), imagem oficial pré-construída, diversidade de temp.
cd /Users/danielpenin/swebench-atomic-ab
: "${DEEPSEEK_API_KEY:?DEEPSEEK_API_KEY is required in env}"
: "${MODAL_TOKEN_ID:?MODAL_TOKEN_ID is required in env}"
: "${MODAL_TOKEN_SECRET:?MODAL_TOKEN_SECRET is required in env}"
export USE_PREBUILT=1
declare -A TEMPS=( [A]=0 [B]=0.4 [C]=0.8 )
for k in A B C; do
  DEEPSEEK_TEMP=${TEMPS[$k]} USE_PREBUILT=1 nohup python3 -u swe_modal_agent.py \
    --ids-file ids-7277.txt --out preds-7277-$k.jsonl --concurrency 1 \
    > /Users/danielpenin/logs/swe-7277-$k.log 2>&1 &
  echo "DeepSeek $k (temp=${TEMPS[$k]}) pid=$!"
done
