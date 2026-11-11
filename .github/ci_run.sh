#!/usr/bin/env bash
# Corre un comando y, si falla, deja las últimas líneas como anotaciones del CI (visibles por la API).
set +e
out=$("$@" 2>&1)
code=$?
echo "$out"
if [ $code -ne 0 ]; then
  echo "$out" | grep -v '^\s*$' | tail -40 | while IFS= read -r l; do
    l=${l//'%'/%25}; echo "::error::${l}"
  done
fi
exit $code
