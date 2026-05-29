#!/bin/bash
# Self-contained train submitter (Slurm only).
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SLEAP_SCRIPT_DIR="${SCRIPT_DIR}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/sleap_common.sh"

fix_script_crlf "${SCRIPT_DIR}"
load_conf
SLEAP_WORK="$(resolve_work)"
ensure_work_dirs "${SLEAP_WORK}"
PKG_DIR="$(training_package_dir "${SLEAP_WORK}")"
ZIP_ARG="${1:-${SLEAP_TRAINING_ZIP:-labels.v001.slp.training_job.zip}}"
RUN_NAME="${2:-${SLEAP_RUN_NAME:-rat_v001}}"
ACCOUNT="${SLEAP_SLURM_ACCOUNT:-gid0}"
MAIL="${SLEAP_MAIL_USER:-${USER}@umich.edu}"
PART="${SLEAP_GPU_PARTITION:-gpu}"
GPU="${SLEAP_GPU_REQUEST:-v100:1}"

echo "SLEAP_WORK=${SLEAP_WORK}"
echo "Training packages: ${PKG_DIR}/"

if ! ZIP_PATH="$(resolve_training_zip "${SLEAP_WORK}" "${ZIP_ARG}")"; then
  echo "training zip not found: ${ZIP_PATH}"
  echo "Export the training job zip from the GUI to: ${PKG_DIR}/"
  exit 1
fi

BUILD_DIR="${PKG_DIR}/.build/${RUN_NAME}"
mkdir -p "${BUILD_DIR}"
unzip -o "${ZIP_PATH}" -d "${BUILD_DIR}" >/dev/null
PKG_SLP="$(find "${BUILD_DIR}" -maxdepth 1 -name '*.pkg.slp' -print -quit 2>/dev/null || true)"
if [[ -z "${PKG_SLP}" || ! -f "${BUILD_DIR}/single_instance.yaml" ]]; then
  echo "zip missing required files: single_instance.yaml and *.pkg.slp"
  echo "  zip: ${ZIP_PATH}"
  exit 1
fi
PKG_SLP="$(basename "${PKG_SLP}")"

cat > "${SLEAP_WORK}/train_job.sbatch" <<EOF
#!/bin/bash
#SBATCH --job-name=sleap_train
#SBATCH --account=${ACCOUNT}
#SBATCH --partition=${PART}
#SBATCH --gpus=${GPU}
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${MAIL}
#SBATCH --output=slurm-%j.out
set -e
source /etc/profile || true
module purge || true
module load ${SLEAP_PYTHON_MODULE:-python/3.11.5}
module load cuda/11.8.0 || true
source ~/sleap_env/bin/activate
cd "${BUILD_DIR}"
~/sleap_env/bin/sleap-nn train single_instance.yaml \
  "data_config.train_labels_path=[${PKG_SLP}]" \
  trainer_config.trainer_accelerator=cuda \
  trainer_config.ckpt_dir="${SLEAP_WORK}/models" \
  trainer_config.run_name="${RUN_NAME}" \
  trainer_config.train_data_loader.num_workers=0 \
  trainer_config.val_data_loader.num_workers=0
EOF
chmod +x "${SLEAP_WORK}/train_job.sbatch"

echo "Training zip: ${ZIP_PATH}"
echo "Submitting training on Slurm (build dir: ${BUILD_DIR})"
JOBID="$(sbatch --parsable "${SLEAP_WORK}/train_job.sbatch")"
echo "Submitted ${JOBID}"
echo "Log: tail -f ${SLEAP_WORK}/slurm-${JOBID}.out"
echo "Model dir: ${SLEAP_WORK}/models/${RUN_NAME}/"
