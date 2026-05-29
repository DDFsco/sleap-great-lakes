#!/bin/bash
# Shared helpers for SLEAP-GL scripts (Great Lakes).

load_conf() {
  local script_dir="${SLEAP_SCRIPT_DIR:-}"
  for conf in "${HOME}/sleap_gl.conf" "${script_dir}/sleap_gl.conf" "${SLEAP_GL_CONF:-}"; do
    if [[ -n "${conf}" ]] && [[ -f "${conf}" ]]; then
      # shellcheck source=/dev/null
      source "${conf}"
      return 0
    fi
  done
}

resolve_work() {
  if [[ -n "${SLEAP_SCRATCH_DIR:-}" ]]; then
    echo "${SLEAP_SCRATCH_DIR}"
    return 0
  fi
  if [[ -n "${SCRATCH:-}" ]]; then
    echo "${SCRATCH}/sleap_rat"
    return 0
  fi
  local account="${SLEAP_SLURM_ACCOUNT:-gid0}"
  local user_name="${USER:-$(whoami)}"
  for root in /scratch/*_root /scratch/*; do
    [[ -d "${root}/${account}/${user_name}" ]] || continue
    echo "${root}/${account}/${user_name}/sleap_rat"
    return 0
  done
  echo "${HOME}/sleap_rat"
}

ensure_work_dirs() {
  local work="$1"
  mkdir -p "${work}"/{labels,videos,models,exports,jobs,training_package}
}

training_package_dir() {
  local work="$1"
  echo "${work}/${SLEAP_TRAINING_PKG_DIR:-training_package}"
}

resolve_training_zip() {
  local work="$1"
  local zip_arg="$2"
  local pkg_dir base

  pkg_dir="$(training_package_dir "${work}")"
  mkdir -p "${pkg_dir}"

  if [[ "${zip_arg}" == /* ]]; then
    echo "${zip_arg}"
    return 0
  fi

  base="$(basename "${zip_arg}")"
  if [[ -f "${pkg_dir}/${base}" ]]; then
    echo "${pkg_dir}/${base}"
    return 0
  fi

  # Allow passing path relative to SLEAP_WORK, e.g. training_package/foo.zip
  if [[ -f "${work}/${zip_arg}" ]]; then
    echo "${work}/${zip_arg}"
    return 0
  fi

  echo "${pkg_dir}/${base}"
  return 1
}

fix_script_crlf() {
  local dir="${1:-${SLEAP_SCRIPT_DIR:-}}"
  local f
  [[ -n "${dir}" ]] || return 0
  for f in "${dir}"/*.sh "${dir}/sleap_gl.conf"; do
    [[ -f "${f}" ]] || continue
    if grep -q $'\r' "${f}" 2>/dev/null; then
      sed -i 's/\r$//' "${f}" 2>/dev/null || tr -d '\r' < "${f}" > "${f}.lf" && mv "${f}.lf" "${f}"
      echo "Fixed CRLF: ${f}"
    fi
  done
}

bootstrap_user_conf() {
  local script_dir="${SLEAP_SCRIPT_DIR:-}"
  local template="${script_dir}/sleap_gl.conf"
  local user_conf="${HOME}/sleap_gl.conf"
  local work account user_name

  [[ -f "${template}" ]] || return 0

  if [[ ! -f "${user_conf}" ]]; then
    cp "${template}" "${user_conf}"
    account="${SLEAP_SLURM_ACCOUNT:-gid0}"
    user_name="${USER:-$(whoami)}"
    sed -i "s/YOUR_UNIQNAME/${user_name}/g" "${user_conf}" 2>/dev/null || true
    echo "Created ${user_conf} — edit SLEAP_SLURM_ACCOUNT if needed."
  fi

  load_conf
  work="$(resolve_work)"
  if ! grep -q '^SLEAP_SCRATCH_DIR=' "${user_conf}" 2>/dev/null; then
    echo "SLEAP_SCRATCH_DIR=${work}" >> "${user_conf}"
    echo "Set SLEAP_SCRATCH_DIR=${work} in ${user_conf}"
  fi
}

remove_cv2_qt_plugins() {
  local venv="${1:-${HOME}/sleap_gui_env}"
  local pyver="$2"
  local cv2_qt="${venv}/lib/python${pyver}/site-packages/cv2/qt/plugins"
  if [[ -d "${cv2_qt}" ]]; then
    rm -rf "${cv2_qt}"
  fi
}

setup_qt_env() {
  local venv="${1:-${HOME}/sleap_gui_env}"
  local py="${venv}/bin/python"
  local pyside_qt pyside_lib pyside_plugins libdir

  pyside_qt="$("${py}" -c 'import os, PySide6; print(os.path.join(os.path.dirname(PySide6.__file__), "Qt"))')"
  pyside_lib="${pyside_qt}/lib"
  pyside_plugins="${pyside_qt}/plugins"

  unset QT_PLUGIN_PATH
  unset QT_QPA_PLATFORM_PLUGIN_PATH
  export QT_QPA_PLATFORM=xcb
  export QT_X11_NO_MITSHM=1
  export LIBGL_ALWAYS_SOFTWARE=1
  export LD_LIBRARY_PATH="${pyside_lib}:${LD_LIBRARY_PATH:-}"
  export QT_PLUGIN_PATH="${pyside_plugins}"

  for libdir in /usr/lib64 /usr/lib /lib64 /lib; do
    if ls "${libdir}"/libxcb-cursor.so* &>/dev/null; then
      export LD_LIBRARY_PATH="${libdir}:${LD_LIBRARY_PATH}"
    fi
  done
}

install_sleap_nn_in_gui_env() {
  local venv="${HOME}/sleap_gui_env"
  local pip="${venv}/bin/pip"
  local py="${venv}/bin/python"
  local sleap_nn_ver="${SLEAP_NN_VERSION:-0.1.3}"
  local sleap_io_ver="${SLEAP_IO_VERSION:-0.6.5}"
  local pyside_ver="${SLEAP_PYSIDE6_VERSION:-6.4.3}"
  local pyver

  [[ -x "${pip}" ]] || { echo "Missing ${venv}. Run: bash install.sh --gui-only"; return 1; }

  echo "Installing sleap-nn ${sleap_nn_ver} into GUI env (for Predict -> Run Training)..."
  "${pip}" install "sleap-io==${sleap_io_ver}" "sleap-nn==${sleap_nn_ver}"
  "${pip}" install --force-reinstall torch torchvision --index-url https://download.pytorch.org/whl/cu118
  "${pip}" install "numpy<2" --force-reinstall
  "${pip}" install "PySide6==${pyside_ver}" "shiboken6==${pyside_ver}" --force-reinstall
  "${pip}" uninstall -y opencv-python opencv-contrib-python 2>/dev/null || true
  "${pip}" install "opencv-python-headless==${SLEAP_OPENCV_HEADLESS_VERSION:-4.8.1.78}"

  pyver="$("${py}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  remove_cv2_qt_plugins "${venv}" "${pyver}"

  "${py}" -c "import sleap_nn; print('sleap-nn OK')"
  sleap-nn --version 2>/dev/null || "${pip}" show sleap-nn | grep '^Version:' || true
  "${py}" -c "import numpy, PySide6; print('numpy', numpy.__version__, 'PySide6', PySide6.__version__)"
}

ensure_gui_python_packages() {
  local venv="${HOME}/sleap_gui_env"
  local pip="${venv}/bin/pip"
  local py="${venv}/bin/python"
  local pyside_ver="${SLEAP_PYSIDE6_VERSION:-6.4.3}"
  local pyver numpy_ver pyside_installed need_fix=0

  [[ -x "${pip}" ]] || { echo "Missing ${venv}. Run: bash install.sh --gui-only"; return 1; }

  pyver="$("${py}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  remove_cv2_qt_plugins "${venv}" "${pyver}"

  numpy_ver="$("${py}" -c 'import numpy; print(numpy.__version__)' 2>/dev/null || echo "missing")"
  pyside_installed="$("${py}" -c 'import PySide6; print(PySide6.__version__)' 2>/dev/null || echo "missing")"

  if [[ "${numpy_ver}" == 2.* ]]; then
    need_fix=1
  fi
  if [[ "${pyside_installed}" != "${pyside_ver}" ]] && [[ "${pyside_installed}" != 6.4.* ]]; then
    if [[ "${pyside_installed}" == 6.5* ]] || [[ "${pyside_installed}" == 6.6* ]] || \
       [[ "${pyside_installed}" == 6.7* ]] || [[ "${pyside_installed}" == 6.8* ]] || \
       [[ "${pyside_installed}" == 6.9* ]] || [[ "${pyside_installed}" == 6.1[0-9]* ]]; then
      need_fix=1
    fi
  fi

  if [[ "${need_fix}" -eq 1 ]]; then
    echo "Repairing GUI packages (numpy<2, PySide6==${pyside_ver})..."
    "${pip}" uninstall -y opencv-python opencv-contrib-python 2>/dev/null || true
    "${pip}" install "opencv-python-headless==${SLEAP_OPENCV_HEADLESS_VERSION:-4.8.1.78}"
    "${pip}" install "PySide6==${pyside_ver}" "shiboken6==${pyside_ver}" "numpy<2" --force-reinstall
    remove_cv2_qt_plugins "${venv}" "${pyver}"
  fi

  if ! "${py}" -c "import sleap_nn" 2>/dev/null; then
    if [[ "${SLEAP_GUI_INSTALL_NN:-1}" == "1" ]]; then
      install_sleap_nn_in_gui_env
    fi
  fi

  "${py}" -c "import numpy, PySide6; print('GUI packages OK: numpy', numpy.__version__, 'PySide6', PySide6.__version__)"
}

verify_gui_env() {
  local venv="${HOME}/sleap_gui_env"
  [[ -d "${venv}" ]] || { echo "FAIL: missing ${venv}"; return 1; }
  # shellcheck source=/dev/null
  source "${venv}/bin/activate"
  python -c "import sleap, sleap_io, numpy, PySide6; print('sleap', sleap.__version__, 'numpy', numpy.__version__, 'PySide6', PySide6.__version__)"
  python -c "import numpy; assert numpy.__version__.startswith('1.'), 'numpy must be 1.x'"
  python -c "import PySide6; v=PySide6.__version__; assert v.startswith('6.4.'), f'PySide6 must be 6.4.x, got {v}'"
  if [[ "${SLEAP_GUI_INSTALL_NN:-1}" == "1" ]]; then
    python -c "import sleap_nn; print('sleap-nn', sleap_nn.__version__ if hasattr(sleap_nn,'__version__') else 'import ok')"
    sleap-nn --version 2>/dev/null || true
  fi
  if type deactivate &>/dev/null; then deactivate; fi
}
