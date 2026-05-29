#!/bin/bash
# Self-contained predict submitter (Slurm only).
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SLEAP_SCRIPT_DIR="${SCRIPT_DIR}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/sleap_common.sh"

fix_script_crlf "${SCRIPT_DIR}"
load_conf
SLEAP_WORK="$(resolve_work)"
ensure_work_dirs "${SLEAP_WORK}"
ACCOUNT="${SLEAP_SLURM_ACCOUNT:-gid0}"
MAIL="${SLEAP_MAIL_USER:-${USER}@umich.edu}"
PART="${SLEAP_GPU_PARTITION:-gpu}"
GPU="${SLEAP_GPU_REQUEST:-v100:1}"
DEFAULT_MODEL="models/${SLEAP_RUN_NAME:-rat_v001}"

submit_one() {
  local video="$1"
  local model="${2:-${DEFAULT_MODEL}}"
  local base output jobfile jobid
  base="$(basename "${video}")"
  base="${base%.*}"
  output="exports/${base}.predicted.slp"
  jobfile="predict_${base}.sbatch"

  cat > "${jobfile}" <<EOF
#!/bin/bash
#SBATCH --job-name=sleap_pred_${base}
#SBATCH --account=${ACCOUNT}
#SBATCH --partition=${PART}
#SBATCH --gpus=${GPU}
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${MAIL}
#SBATCH --output=slurm-predict-%j.out
set -e
source /etc/profile || true
module purge || true
module load ${SLEAP_PYTHON_MODULE:-python/3.11.5}
module load cuda/11.8.0 || true
source ~/sleap_env/bin/activate
cd "${SLEAP_WORK}"
~/sleap_env/bin/sleap-nn track -m "${model}" -i "${video}" -o "${output}" --device cuda
EOF
  chmod +x "${jobfile}"
  jobid="$(sbatch --parsable "${jobfile}")"
  echo "Submitted ${jobid}: ${video} -> ${output}"
}

mkdir -p "${SLEAP_WORK}/videos" "${SLEAP_WORK}/exports"
cd "${SLEAP_WORK}"
echo "SLEAP_WORK=${SLEAP_WORK}"

if [[ "${1:-}" == "--all" ]]; then
  model="${2:-${DEFAULT_MODEL}}"
  shopt -s nullglob
  vids=(videos/*.mp4 videos/*.avi videos/*.MP4 videos/*.AVI)
  if [[ ${#vids[@]} -eq 0 ]]; then
    echo "no videos found in ${SLEAP_WORK}/videos/"
    exit 1
  fi
  [[ -d "${model}" ]] || { echo "model not found: ${SLEAP_WORK}/${model}"; exit 1; }
  for v in "${vids[@]}"; do submit_one "${v}" "${model}"; done
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: bash predict.sh <video> [model_dir]"
  echo "   or: bash predict.sh --all [model_dir]"
  exit 1
fi

video="$1"
model="${2:-${DEFAULT_MODEL}}"
[[ -f "${video}" ]] || { echo "video not found: ${SLEAP_WORK}/${video}"; exit 1; }
[[ -d "${model}" ]] || { echo "model not found: ${SLEAP_WORK}/${model}"; exit 1; }
submit_one "${video}" "${model}"
