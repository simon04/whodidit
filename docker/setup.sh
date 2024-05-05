#!/bin/bash
set -euo pipefail
/parse_osc.pl \
  --host "${MYSQL_SERVER_HOST}" \
  --user "${MYSQL_USER}" \
  --password "${MYSQL_PASSWORD}" \
  --database "${MYSQL_DATABASE}" \
  --clear \
  --verbose
