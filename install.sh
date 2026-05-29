#!/bin/bash
# Self-contained install/check/gpu-test for Great Lakes SLEAP pipeline.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SLEAP_SCRIPT_DIR="${SCRIPT_DIR}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/sleap_common.sh"

MODE="${1:-install}"

setup_gui_env() {
  local py_module="${SLEAP_GUI_PYTHON_MODULE:-python/3.11.5}"
  local sleap_ver="${SLEAP_VERSION:-1.6.1}"
  local sleap_io_ver="${SLEAP_IO_VERSION:-0.6.5}"
  local pyside_ver="${SLEAP_PYSIDE6_VERSION:-6.4.3}"
  local venv="${HOME}/sleap_gui_env"
  local pyver

  module purge
  module load "${py_module}"

  [[ -d "${venv}" ]] && rm -rf "${venv}"
  python -m venv "${venv}"
  # shellcheck source=/dev/null
  source "${venv}/bin/activate"
  pip install --upgrade pip wheel
  pip install "numpy<2"
  pip install "sleap-io[all]==${sleap_io_ver}" "sleap==${sleap_ver}"
  pip uninstall -y opencv-python opencv-contrib-python 2>/dev/null || true
  pip install "opencv-python-headless==${SLEAP_OPENCV_HEADLESS_VERSION:-4.8.1.78}"
  pip install "PySide6==${pyside_ver}" "shiboken6==${pyside_ver}" --force-reinstall
  pip install "numpy<2" --force-reinstall
  pyver="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  remove_cv2_qt_plugins "${venv}" "${pyver}"
  if [[ "${SLEAP_GUI_INSTALL_NN:-1}" == "1" ]]; then
    if type deactivate &>/dev/null; then deactivate; fi
    load_conf
    install_sleap_nn_in_gui_env
  fi
  verify_gui_env
  if type deactivate &>/dev/null; then deactivate; fi
}

setup_train_env() {
  local py_module="${SLEAP_PYTHON_MODULE:-python/3.11.5}"
  local sleap_io_ver="${SLEAP_IO_VERSION:-0.6.5}"
  local sleap_nn_ver="${SLEAP_NN_VERSION:-0.1.3}"
  local venv="${HOME}/sleap_env"

  module purge
  module load "${py_module}"
  module load cuda/11.8.0

  [[ -d "${venv}" ]] && rm -rf "${venv}"
  python -m venv "${venv}"
  # shellcheck source=/dev/null
  source "${venv}/bin/activate"
  pip install --upgrade pip wheel
  pip install "sleap-io==${sleap_io_ver}" "sleap-nn==${sleap_nn_ver}"
  pip install --force-reinstall torch torchvision --index-url https://download.pytorch.org/whl/cu118
  sleap-nn --version 2>/dev/null || pip show sleap-nn | grep '^Version:' || true
  deactivate || true
}

run_check() {
  echo "SLEAP_WORK=$(resolve_work)"
  echo ""
  if [[ -d "${HOME}/sleap_gui_env" ]]; then
    verify_gui_env || return 1
  else
    echo "MISSING: ~/sleap_gui_env"
    return 1
  fi
  echo ""
  echo "=== check train env ==="
  if [[ -d "${HOME}/sleap_env" ]]; then
    # shellcheck source=/dev/null
    source "${HOME}/sleap_env/bin/activate"
    python -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"
    sleap-nn --version 2>/dev/null || pip show sleap-nn | grep '^Version:' || true
    deactivate || true
  else
    echo "MISSING: ~/sleap_env"
    return 1
  fi
  echo ""
  echo "All checks passed."
}

run_gpu_test() {
  local account="${SLEAP_SLURM_ACCOUNT:-gid0}"
  local part="${SLEAP_GPU_PARTITION:-gpu}"
  local req="${SLEAP_GPU_REQUEST:-v100:1}"
  srun --account="${account}" --partition="${part}" --gpus="${req}" --mem=8G --time=00:10:00 \
    bash -lc 'source ~/sleap_env/bin/activate && python -c "import torch; print(torch.cuda.is_available())"'
}

fix_script_crlf "${SCRIPT_DIR}"
bootstrap_user_conf
load_conf
SLEAP_WORK="$(resolve_work)"
ensure_work_dirs "${SLEAP_WORK}"
echo "SLEAP_WORK=${SLEAP_WORK}"

case "${MODE}" in
  install|"")
    setup_gui_env
    setup_train_env
    chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true
    echo ""
    echo "Install complete."
    echo "  Config:  ~/sleap_gl.conf"
    echo "  Work:    ${SLEAP_WORK}"
    echo "  Label:   bash ${SCRIPT_DIR}/label.sh   (OOD Remote Desktop only)"
    echo "  Train:   bash ${SCRIPT_DIR}/train.sh   (SSH login node)"
    echo "  Predict: bash ${SCRIPT_DIR}/predict.sh (SSH login node)"
    ;;
  --gui-only)
    setup_gui_env
    echo "GUI env reinstall done."
    ;;
  --gui-add-nn)
    load_conf
    install_sleap_nn_in_gui_env
    verify_gui_env
    echo "sleap-nn added to GUI env. Restart sleap-label, then try Predict -> Run Training."
    ;;
  --check)
    run_check
    ;;
  --gpu-test)
    run_gpu_test
    ;;
  --fix-crlf)
    fix_script_crlf "${SCRIPT_DIR}"
    echo "CRLF fix done for ${SCRIPT_DIR}"
    ;;
  *)
    echo "Usage: bash install.sh [install|--check|--gpu-test|--gui-only|--gui-add-nn|--fix-crlf]"
    exit 1
    ;;
esac
