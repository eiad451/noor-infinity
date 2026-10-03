#!/bin/bash
cd "$(dirname "$0")"
if [ -f node_modules/.bin/next ]; then
  exec node_modules/.bin/next start -p "${PORT:-3000}"
else
  echo "Run: pnpm install first"
  exit 1
fi
