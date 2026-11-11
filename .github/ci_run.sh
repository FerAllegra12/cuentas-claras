#!/usr/bin/env bash
# Corre un comando y, si falla, deja el final de la salida (sin barras de progreso) como UNA anotación del CI.
set +e
out=$("$@" 2>&1)
code=$?
echo "$out"
if [ $code -ne 0 ]; then
  msg=$(echo "$out" | grep -vE 'Unzipping|^\s*\[[=> ]+\]|^\s*$|^✅' | tail -60 | cut -c1-300)
  msg=${msg//'%'/%25}
  msg=${msg//$'\n'/%0A}
  echo "::error title=Fallo: $1 $2::${msg:0:3800}"
fi
exit $code
