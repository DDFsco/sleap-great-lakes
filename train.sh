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
ZIP="${1:-${SLEAP_TRAINING_ZIP:-labels.v001.slp.training_job.zip}}"
RUN_NAME="${2:-${SLEAP_RUN_NAME:-rat_v001}}"
ACCOUNT="${SLEAP_SLURM_ACCOUNT:-gid0}"
MAIL="${SLEAP_MAIL_USER:-${USER}@umich.edu}"
PART="${SLEAP_GPU_PARTITION:-gpu}"
GPU="${SLEAP_GPU_REQUEST:-v100:1}"

mkdir -p "${SLEAP_WORK}"
cd "${SLEAP_WORK}"
echo "SLEAP_WORK=${SLEAP_WORK}"
[[ "${ZIP}" == /* ]] && cp "${ZIP}" . && ZIP="$(basename "${ZIP}")"
if [[ ! -f "${ZIP}" ]] && [[ -f "${HOME}/$(basename "${ZIP}")" ]]; then
  cp "${HOME}/$(basename "${ZIP}")" .
  ZIP="$(basename "${ZIP}")"
fi
if [[ ! -f "${ZIP}" ]]; then
  echo "training zip not found. put it in ${SLEAP_WORK}/ or pass absolute path."
  exit 1
fi

unzip -o "${ZIP}" >/dev/null
PKG_SLP="$(ls *.pkg.slp 2>/dev/null | head -n 1 || true)"
if [[ -z "${PKG_SLP}" || ! -f single_instance.yaml ]]; then
  echo "zip missing required files: single_instance.yaml and *.pkg.slp"
  exit 1
fi

cat > train_job.sbatch <<EOF
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
cd "${SLEAP_WORK}"
~/sleap_env/bin/sleap-nn train single_instance.yaml \
  "data_config.train_labels_path=[${PKG_SLP}]" \
  trainer_config.trainer_accelerator=cuda \
  trainer_config.ckpt_dir=models \
  trainer_config.run_name="${RUN_NAME}" \
  trainer_config.train_data_loader.num_workers=0 \
  trainer_config.val_data_loader.num_workers=0
EOF
chmod +x train_job.sbatch

echo "Submitting training on Slurm from ${SLEAP_WORK}"
JOBID="$(sbatch --parsable train_job.sbatch)"
echo "Submitted ${JOBID}"
echo "Log: tail -f ${SLEAP_WORK}/slurm-${JOBID}.out"
echo "Model dir: ${SLEAP_WORK}/models/${RUN_NAME}/"
