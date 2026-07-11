#!/bin/bash
# All PoC seeds (oss-fuzz + native + bugzilla + external) now live under one
# unified R2 prefix, seeds/<project>/<id>.bin. The old native-seeds/ prefix was
# retired, so this is a thin wrapper over download_seeds.sh for the native
# (real-program replay) workflows that still call it.
exec "$(dirname "$0")/download_seeds.sh" "$@"
