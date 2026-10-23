#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail
media=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec bash "$media/E610-CentOS7.9-adaptation-r2.run" "$@"
