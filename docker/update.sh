#!/bin/bash
set -euo pipefail

test -e /update.sh.lock && exit 0
touch /update.sh.lock
trap 'rm /update.sh.lock' EXIT

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
