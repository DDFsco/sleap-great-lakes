# SLEAP on UMich Great Lakes

Minimal, lab-tested pipeline for [SLEAP](https://sleap.ai) pose tracking on [Great Lakes](https://arc.umich.edu/great-lakes/).

**Four entry points:** `install.sh` → `label.sh` → `train.sh` → `predict.sh`

- **Labeling** — manual, in Open OnDemand Remote Desktop (GUI)
- **Training & prediction** — Slurm GPU jobs only (SSH login node submits jobs)

Verified end-to-end on Great Lakes (May 2026): label → export training zip → GPU train → full-video predict.

## Quick start (new lab member)

### 1. Get the scripts onto Great Lakes

Clone or upload this folder to `~/gl_sync/` on Great Lakes.

**Option A — git (if repo is public and GL has network):**

```bash
git clone https://github.com/DDFsco/sleap-great-lakes.git ~/gl_sync
```

**Option B — upload from your laptop (recommended):**

Use **Open OnDemand → Files → Upload**, or **sftp** (plain `scp` can break with Duo/bashrc output):

```bash
sftp uniqname@greatlakes.arc-ts.umich.edu
put -r gl_sync gl_sync
```

Extract if you uploaded a tarball:

```bash
tar -xzf gl_sync.tar.gz -C ~/
```

### 2. One-time install (SSH login node)

```bash
bash ~/gl_sync/install.sh --fix-crlf   # once, if uploaded from Mac/Windows
bash ~/gl_sync/install.sh
bash ~/gl_sync/install.sh --check
bash ~/gl_sync/install.sh --gpu-test   # optional: confirms CUDA on a GPU node
```

This creates:

| Path | Purpose |
|------|---------|
| `~/sleap_gui_env` | SLEAP GUI (`sleap-label`) for OOD labeling |
| `~/sleap_env` | `sleap-nn` for GPU train + predict |
| `~/sleap_gl.conf` | Your config (account, scratch path, version pins) |

Work data lives on **scratch**, not in home:

```text
/scratch/gid_root/gid0/<uniqname>/sleap_rat/
  labels/            .slp label projects
  videos/            raw recordings (.mp4, .avi)
  training_package/  training job zips from GUI export
  models/            trained checkpoints (<run_name>/)
  exports/           predictions (*.predicted.slp)
  jobs/              optional artifacts
```

`install.sh` auto-sets `SLEAP_SCRATCH_DIR` in `~/sleap_gl.conf`. OOD nodes may not define `$SCRATCH`, so scripts always use this explicit path.

### 3. Edit config

```bash
nano ~/sleap_gl.conf
```

Minimum edits for a new user:

```bash
SLEAP_SLURM_ACCOUNT=gid0              # your PI billing account
SLEAP_MAIL_USER=uniqname@umich.edu
SLEAP_SCRATCH_DIR=/scratch/gid_root/gid0/uniqname/sleap_rat
```

Wrong path example (does **not** exist on GL): `/scratch/uniqname/`

### 4. Every experiment

```bash
# Step 1 — Label (OOD Remote Desktop terminal ONLY)
bash ~/gl_sync/label.sh
# Optional: bash ~/gl_sync/label.sh labels/rat_project.slp

# Step 2 — Train (SSH login node, after exporting training zip to training_package/)
bash ~/gl_sync/train.sh labels.v001.slp.training_job.zip rat_v001

# Step 3 — Predict (SSH login node)
bash ~/gl_sync/predict.sh videos/session01.mp4 models/rat_v001
bash ~/gl_sync/predict.sh --all models/rat_v001
```

**Parameters** (paths are relative to `SLEAP_WORK` unless you pass an absolute path):

| Command | Argument | Meaning |
|---------|----------|---------|
| `label.sh` | *(none)* | Opens the default project `labels/rat_project.slp`; creates it if missing |
| `label.sh` | `[project.slp]` | Path to a specific label project under `SLEAP_WORK/labels/` |
| `train.sh` | `[training_zip]` | Filename of the training job zip in `training_package/` (e.g. `labels.v001.slp.training_job.zip`). Default: `SLEAP_TRAINING_ZIP` in `~/sleap_gl.conf` |
| `train.sh` | `[run_name]` | Name for this training run; checkpoints go to `models/<run_name>/`. Use a new name for each attempt (e.g. `rat_v001-2`). Default: `SLEAP_RUN_NAME` in config |
| `predict.sh` | `<video>` | Input video under `videos/` (e.g. `videos/session01.mp4`) |
| `predict.sh` | `[model_dir]` | Trained model folder under `models/` (e.g. `models/rat_v001`). Default: `models/<SLEAP_RUN_NAME>` |
| `predict.sh --all` | `[model_dir]` | Run prediction on every `.mp4`/`.avi` in `videos/` with the given model |

Outputs: training → `models/<run_name>/`; prediction → `exports/<video_basename>.predicted.slp`

Monitor jobs:

```bash
squeue -u $USER
tail -f /scratch/gid_root/gid0/$USER/sleap_rat/slurm-<jobid>.out
```

## Workflow diagram

```text
┌─────────────────┐     export zip      ┌─────────────────────┐     sbatch      ┌─────────────┐
│  label.sh       │ ──────────────────► │ training_package/   │ ──────────────► │  train.sh   │
│  (OOD GUI)      │   Predict→Run       │ *.training_job.zip  │   GPU job       │  (Slurm)    │
│  sleap-label    │   Training…         └─────────────────────┘                 └──────┬──────┘
└─────────────────┘                                                                   │
                                                                                      ▼
                                                                              models/<run_name>/
                                                                                      │
                                                                                      ▼
                                                                              ┌─────────────┐
                                                                              │ predict.sh  │
                                                                              │ (Slurm GPU) │
                                                                              └──────┬──────┘
                                                                                     ▼
                                                                         exports/*.predicted.slp
```

## Labeling (Open OnDemand)

1. Open [Great Lakes Open OnDemand](https://greatlakes-oncampus.arc-ts.umich.edu/) → **Interactive Apps → Remote Desktop**
2. Launch a session, open a terminal inside the desktop
3. Run:

```bash
bash ~/gl_sync/label.sh
```

4. Label diverse frames (aim for 50–500+ for production models; ~25 frames works for smoke tests)
5. **Predict → Run Training…** — configure training, then export the **training job zip** to `SLEAP_WORK/training_package/` (path shown when `label.sh` starts)

**Do not** run `label.sh` over plain SSH — it requires `DISPLAY` from the OOD desktop.

## Training tips (small datasets)

On very small label sets (~25 frames), training can finish without error but produce **0 predicted instances** if heatmap settings are too tight.

| Setting | Failed run | Successful run |
|---------|------------|----------------|
| `sigma` | 2.5 | **5.0** |
| `output_stride` | (default) | 2 |

In the GUI **Run Training** dialog, increase **sigma** to ~5.0 for small datasets. Use a unique `run_name` for each attempt (e.g. `rat_v001-2`).

After training, check the Slurm log for non-zero instance counts on train/val before running predict.

## Script reference

| Script | Where to run | What it does |
|--------|--------------|--------------|
| `install.sh` | SSH login | Create venvs, bootstrap `~/sleap_gl.conf` |
| `install.sh --check` | SSH login | Verify package versions |
| `install.sh --gpu-test` | SSH login | Quick CUDA test via `srun` |
| `install.sh --fix-crlf` | SSH login | Fix Windows/Mac line endings |
| `install.sh --gui-only` | SSH login | Rebuild GUI env only |
| `install.sh --gui-add-nn` | SSH login | Add sleap-nn to existing GUI env |
| `label.sh` | **OOD only** | Open `sleap-label` |
| `train.sh [zip] [run_name]` | SSH login | Submit GPU training job |
| `predict.sh <video> [model]` | SSH login | Submit GPU predict job |
| `predict.sh --all [model]` | SSH login | Predict all videos in `videos/` |
| `fix_gui_qt.sh` | OOD | Repair Qt/numpy/opencv after pip drift |

## Pinned software stack

Default versions (edit in `~/sleap_gl.conf`, then re-run `install.sh`):

| Package | Version | Role |
|---------|---------|------|
| sleap | 1.6.1 | GUI labeling |
| sleap-io | 0.6.5 | Label file I/O |
| sleap-nn | 0.1.3 | GPU train + predict |
| PySide6 | 6.4.3 | Qt GUI (6.5+ needs libxcb-cursor missing on GL) |
| numpy | &lt;2 | Required for PySide6 on GL |
| opencv-python-headless | 4.8.1.78 | Avoids Qt plugin conflicts |

Bump `SLEAP_VERSION`, `SLEAP_IO_VERSION`, and `SLEAP_NN_VERSION` **together** per [SLEAP compatibility table](https://docs.sleap.ai/latest/installation/#version-compatibility).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `$'\r': command not found` | `bash ~/gl_sync/install.sh --fix-crlf` |
| `DISPLAY is not set` | Run `label.sh` in OOD Remote Desktop, not SSH |
| Qt / xcb / libxcb-cursor crash | `bash ~/gl_sync/fix_gui_qt.sh` then `label.sh` |
| NumPy 2.x / PySide6 warnings | Do not `pip install -U` manually; run `install.sh --gui-only` |
| Training OK but 0 predictions | Increase `sigma` in training export; check Slurm log |
| `sbatch: Invalid account` | Set `SLEAP_SLURM_ACCOUNT` in `~/sleap_gl.conf` |
| `training zip not found` | Export zip from GUI to `SLEAP_WORK/training_package/` |
| `cuda False` on login node | Normal — GPU is used inside Slurm jobs |
| scp hangs / fails | Use OOD file upload or `sftp` instead |

## Prerequisites

- [Great Lakes account](https://arc.umich.edu/greatlakes/) with a Slurm billing account from your PI
- Off campus: [UM VPN](https://its.umich.edu/enterprise/wifi-networks/vpn) before SSH/OOD

## File layout (this repo)

```text
gl_sync/
  install.sh          # install / check / gpu-test
  label.sh            # OOD GUI launcher
  train.sh            # Slurm training submitter
  predict.sh          # Slurm prediction submitter
  sleap_common.sh     # shared paths, Qt, config bootstrap
  fix_gui_qt.sh       # GUI env repair
  sleap_gl.conf       # config template (copied to ~/ on install)
  README.md
```

## References

- [SLEAP documentation](https://docs.sleap.ai/latest/)
- [SLEAP-NN FAQ](https://nn.sleap.ai/latest/help/faq/)
- [Great Lakes user guide](https://documentation.its.umich.edu/arc-hpc/greatlakes/user-guide)
