#!/bin/sh
set -eu

case "${1:-} ${2:-}" in
  "bin/jazida_phoenix start"|"/app/bin/jazida_phoenix start")
    bin/jazida_phoenix eval "JazidaPhoenix.Release.migrate()"
    ;;
esac

exec "$@"
