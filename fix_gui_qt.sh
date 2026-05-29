#!/bin/bash
# Repair GUI env: Qt/PySide6, numpy, opencv, and optional sleap-nn.
# Run inside OOD Remote Desktop terminal.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SLEAP_SCRIPT_DIR="${SCRIPT_DIR}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/sleap_common.sh"

load_conf
ensure_gui_python_packages
if [[ "${SLEAP_GUI_INSTALL_NN:-1}" == "1" ]]; then
  install_sleap_nn_in_gui_env
fi
verify_gui_env
echo "Done. Restart sleap-label, then: bash ${SCRIPT_DIR}/label.sh"
