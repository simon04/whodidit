#!/bin/bash
set -euo pipefail
/parse_osc.pl \
  --host "${MYSQL_SERVER_HOST}" \
  --user "${MYSQL_USER}" \
  --password "${MYSQL_PASSWORD}" \
  --database "${MYSQL_DATABASE}" \
  --verbose \
  --url https://planet.openstreetmap.org/replication/hour/ \
  --state /wdi/state.txt \
  --wget /usr/bin/wget \
  ${WDI_UPDATE_BBOX:+--bbox "${WDI_UPDATE_BBOX}"}
