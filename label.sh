#!/bin/bash
# Open SLEAP GUI for manual labeling on Great Lakes OOD Remote Desktop.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SLEAP_SCRIPT_DIR="${SCRIPT_DIR}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/sleap_common.sh"

fix_script_crlf "${SCRIPT_DIR}"
load_conf
SLEAP_WORK="$(resolve_work)"
ensure_work_dirs "${SLEAP_WORK}"

PROJECT="${1:-${SLEAP_LABEL_PROJECT:-labels/rat_project.slp}}"
if [[ "${PROJECT}" != /* ]]; then
  PROJECT="${SLEAP_WORK}/${PROJECT}"
fi
mkdir -p "$(dirname "${PROJECT}")"

VENV="${HOME}/sleap_gui_env"
if [[ ! -x "${VENV}/bin/sleap-label" ]]; then
  echo "Missing GUI env. Run: bash ${SCRIPT_DIR}/install.sh --gui-only"
  exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "ERROR: DISPLAY is not set."
  echo "Run this in Open OnDemand -> Remote Desktop terminal, not plain SSH."
  exit 1
fi

module load "${SLEAP_GUI_PYTHON_MODULE:-python/3.11.5}" 2>/dev/null || true
ensure_gui_python_packages
# shellcheck source=/dev/null
source "${VENV}/bin/activate"
setup_qt_env "${VENV}"

echo "SLEAP_WORK=${SLEAP_WORK}"
echo "Project: ${PROJECT}"

if [[ ! -f "${PROJECT}" ]]; then
  echo "No project file yet — opening sleap-label to create one."
  echo "Save to: ${SLEAP_WORK}/labels/"
  exec sleap-label
fi

echo "After labeling: Predict -> Run Training... -> export zip to $(training_package_dir "${SLEAP_WORK}")/"
exec sleap-label "${PROJECT}"
