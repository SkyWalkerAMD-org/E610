#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec bash "$script_dir/install.sh" --rollback "$@"
