#
# Video -> COLMAP -> 3D Gaussian Splat
# Run from the repository root, inside the gaussian_splatting conda env.
#

import argparse
import os
import shutil
import subprocess
import sys


REPO_ROOT = os.path.dirname(os.path.abspath(__file__))


def run(cmd, cwd=None):
    printable = " ".join(str(c) for c in cmd) if isinstance(cmd, list) else cmd
    print("\n>>", printable, flush=True)
    completed = subprocess.run(cmd, cwd=cwd)
    if completed.returncode != 0:
        raise SystemExit("Command failed with code {}: {}".format(completed.returncode, printable))


def which_or_path(names):
    for name in names:
        found = shutil.which(name)
        if found:
            return found
    return None


def find_ffmpeg(explicit):
    if explicit:
        return explicit
    found = which_or_path(["ffmpeg"])
    if found:
        return found
    raise SystemExit("ffmpeg not found. Run scripts/install_windows.ps1 or add ffmpeg to PATH.")


def find_colmap(explicit):
    if explicit:
        return explicit
    env = os.environ.get("COLMAP_BAT") or os.environ.get("COLMAP_PATH")
    if env and os.path.isfile(env):
        return env
    local_bat = os.path.join(REPO_ROOT, "tools", "colmap", "COLMAP.bat")
    if os.path.isfile(local_bat):
        return local_bat
    found = which_or_path(["colmap", "COLMAP.bat"])
    if found:
        return found
    raise SystemExit(
        "COLMAP not found. Run scripts/install_windows.ps1 "
        "or pass --colmap path\\to\\COLMAP.bat"
    )


def probe_gpu():
    """Return (gpu_name, vram_mb) from nvidia-smi, or (None, None)."""
    try:
        out = subprocess.check_output(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.total",
                "--format=csv,noheader,nounits",
            ],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        line = out.strip().splitlines()[0]
        parts = [p.strip() for p in line.split(",")]
        name = parts[0]
        vram = int(float(parts[-1]))
        return name, vram
    except Exception:
        return None, None


def prefer_nvidia():
    # Laptop hybrid: CUDA only sees the NVIDIA dGPU. Pin device 0.
    os.environ.setdefault("CUDA_VISIBLE_DEVICES", "0")
    os.environ.setdefault("CUDA_DEVICE_ORDER", "PCI_BUS_ID")


def count_images(folder):
    if not os.path.isdir(folder):
        return 0
    exts = {".jpg", ".jpeg", ".png"}
    return sum(1 for name in os.listdir(folder) if os.path.splitext(name)[1].lower() in exts)


def extract_frames(ffmpeg, video, input_dir, fps):
    os.makedirs(input_dir, exist_ok=True)
    for name in os.listdir(input_dir):
        path = os.path.join(input_dir, name)
        if os.path.isfile(path):
            os.remove(path)
    pattern = os.path.join(input_dir, "%04d.jpg")
    run([ffmpeg, "-y", "-i", video, "-vf", "fps={}".format(fps), "-q:v", "2", pattern])
    n = count_images(input_dir)
    if n < 15:
        raise SystemExit("Only {} frames extracted. Need more overlap or a higher --fps.".format(n))
    print("Extracted {} frames into {}".format(n, input_dir), flush=True)


def convert_scene(work, colmap, use_gpu, overlap):
    cmd = [
        sys.executable,
        os.path.join(REPO_ROOT, "convert.py"),
        "-s", work,
        "--colmap_executable", colmap,
        "--matcher", "sequential",
        "--overlap", str(overlap),
    ]
    if not use_gpu:
        cmd.append("--no_gpu")
    run(cmd, cwd=REPO_ROOT)


def sparse_ready(work):
    sparse0 = os.path.join(work, "sparse", "0")
    needed = ["cameras.bin", "images.bin", "points3D.bin"]
    return all(os.path.isfile(os.path.join(sparse0, name)) for name in needed)


def wipe_sfm(work):
    for name in ("distorted", "sparse", "images", "stereo"):
        path = os.path.join(work, name)
        if os.path.isdir(path):
            shutil.rmtree(path)


def train_flags_for_vram(vram_mb, gpu_name, iterations_override):
    if vram_mb is None:
        vram_mb = 6144
        print("Could not read GPU VRAM; assuming 6 GB laptop profile.", flush=True)

    gpu_name = gpu_name or "unknown"
    print("GPU: {} ({} MB)".format(gpu_name, vram_mb), flush=True)
    extra = []
    laptop_6gb = vram_mb < 7000 or "2060" in gpu_name
    if laptop_6gb:
        iterations = 7000
        extra = [
            "--densify_until_iter", "5000",
            "--densify_grad_threshold", "0.0006",
            "--data_device", "cpu",
        ]
        print("Training profile: 6 GB laptop (RTX 2060 class).", flush=True)
    elif vram_mb < 10000:
        iterations = 15000
        extra = [
            "--densify_until_iter", "10000",
            "--densify_grad_threshold", "0.0003",
            "--data_device", "cpu",
        ]
    elif vram_mb < 16000:
        iterations = 30000
        extra = ["--data_device", "cuda"]
    else:
        iterations = 30000

    if iterations_override:
        iterations = iterations_override

    flags = [
        "--disable_viewer",
        "--test_iterations", "-1",
        "--iterations", str(iterations),
        "--save_iterations", str(iterations),
    ] + extra
    return flags, iterations


def train_scene(work, model_path, extra_flags):
    cmd = [
        sys.executable,
        os.path.join(REPO_ROOT, "train.py"),
        "-s", work,
        "-m", model_path,
    ] + extra_flags
    run(cmd, cwd=REPO_ROOT)


def main():
    parser = argparse.ArgumentParser(
        description="Generate a 3D Gaussian splat from a video (ffmpeg + COLMAP + train.py)."
    )
    parser.add_argument("--video", required=True, help="Path to the input video")
    parser.add_argument("--work", default="", help="Working folder (default: <video_dir>/<video_stem>_splat)")
    parser.add_argument("--fps", type=float, default=1.0, help="Frames per second to extract (default: 1)")
    parser.add_argument("--overlap", type=int, default=15, help="COLMAP sequential match overlap")
    parser.add_argument("--iterations", type=int, default=0, help="Override training iterations (0 = auto by VRAM)")
    parser.add_argument("--ffmpeg", default="", help="ffmpeg executable")
    parser.add_argument("--colmap", default="", help="COLMAP.bat (Windows) or colmap binary")
    parser.add_argument("--cpu-sfm", action="store_true", help="Force COLMAP SIFT on CPU")
    parser.add_argument("--skip-extract", action="store_true", help="Reuse existing work/input frames")
    parser.add_argument("--skip-sfm", action="store_true", help="Reuse existing COLMAP sparse/0")
    parser.add_argument("--skip-train", action="store_true", help="Stop after COLMAP")
    args = parser.parse_args()

    video = os.path.abspath(args.video)
    if not os.path.isfile(video):
        raise SystemExit("Video not found: {}".format(video))

    if args.work:
        work = os.path.abspath(args.work)
    else:
        stem = os.path.splitext(os.path.basename(video))[0]
        work = os.path.join(os.path.dirname(video), stem + "_splat")

    input_dir = os.path.join(work, "input")
    model_path = os.path.join(work, "output")
    os.makedirs(work, exist_ok=True)

    ffmpeg = find_ffmpeg(args.ffmpeg or None)
    colmap = find_colmap(args.colmap or None)
    prefer_nvidia()
    gpu_name, vram = probe_gpu()
    print("ffmpeg:", ffmpeg)
    print("colmap:", colmap)
    print("work:  ", work)
    if gpu_name:
        print("nvidia-smi:", gpu_name, "{} MB".format(vram))
    else:
        print("nvidia-smi: not found (training will fail without an NVIDIA GPU)")

    if not args.skip_extract:
        extract_frames(ffmpeg, video, input_dir, args.fps)
    elif count_images(input_dir) < 15:
        raise SystemExit("Not enough frames in {}".format(input_dir))

    if not args.skip_sfm:
        if sparse_ready(work):
            print("Existing COLMAP model found; deleting it to rebuild.", flush=True)
        wipe_sfm(work)
        try_gpu = not args.cpu_sfm
        try:
            convert_scene(work, colmap, use_gpu=try_gpu, overlap=args.overlap)
        except SystemExit:
            if not try_gpu:
                raise
            print("GPU SIFT failed; retrying COLMAP on CPU...", flush=True)
            wipe_sfm(work)
            convert_scene(work, colmap, use_gpu=False, overlap=args.overlap)
            try_gpu = False
        if not sparse_ready(work) and try_gpu:
            print("COLMAP GPU run incomplete; retrying on CPU...", flush=True)
            wipe_sfm(work)
            convert_scene(work, colmap, use_gpu=False, overlap=args.overlap)
        if not sparse_ready(work):
            raise SystemExit("COLMAP finished but sparse/0 is incomplete. Capture needs more overlap.")
        n_undist = count_images(os.path.join(work, "images"))
        print("COLMAP registered {} undistorted images.".format(n_undist), flush=True)
        if n_undist < 20:
            print("Warning: few registered cameras; splat quality will be limited.", flush=True)
    elif not sparse_ready(work):
        raise SystemExit("--skip-sfm set but {}/sparse/0 is not ready".format(work))

    if args.skip_train:
        print("Skipping training. COLMAP dataset is ready at", work)
        return

    extra, iters = train_flags_for_vram(vram, gpu_name, args.iterations or None)
    print("Training for {} iterations...".format(iters), flush=True)
    train_scene(work, model_path, extra)

    ply = os.path.join(model_path, "point_cloud", "iteration_{}".format(iters), "point_cloud.ply")
    print("\nSplat ready:")
    print(" ", ply if os.path.isfile(ply) else model_path)


if __name__ == "__main__":
    main()
