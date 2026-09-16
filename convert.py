#
# Copyright (C) 2023, Inria
# GRAPHDECO research group, https://team.inria.fr/graphdeco
# All rights reserved.
#
# This software is free for non-commercial, research and evaluation use
# under the terms of the LICENSE.md file.
#
# For inquiries contact  george.drettakis@inria.fr
#

import os
import logging
import subprocess
from argparse import ArgumentParser
import shutil

parser = ArgumentParser("Colmap converter")
parser.add_argument("--no_gpu", action='store_true')
parser.add_argument("--skip_matching", action='store_true')
parser.add_argument("--source_path", "-s", required=True, type=str)
parser.add_argument("--camera", default="OPENCV", type=str)
parser.add_argument("--colmap_executable", default="", type=str)
parser.add_argument("--resize", action="store_true")
parser.add_argument("--magick_executable", default="", type=str)
parser.add_argument("--matcher", default="exhaustive", choices=["exhaustive", "sequential"],
                    help="exhaustive for photo sets; sequential for video frames")
parser.add_argument("--overlap", default=15, type=int,
                    help="SequentialMatching.overlap when --matcher sequential")
args = parser.parse_args()
args.source_path = os.path.abspath(args.source_path)

colmap_exe = args.colmap_executable if args.colmap_executable else "colmap"
magick_exe = args.magick_executable if args.magick_executable else "magick"
use_gpu = "1" if not args.no_gpu else "0"
src = args.source_path
input_dir = os.path.join(src, "input")
db_path = os.path.join(src, "distorted", "database.db")
distorted_sparse = os.path.join(src, "distorted", "sparse")


def run_colmap(argv):
    if os.name == "nt" and colmap_exe.lower().endswith(".bat"):
        cmd = ["cmd", "/c", colmap_exe] + argv
    else:
        cmd = [colmap_exe] + argv
    print(">>", " ".join(cmd), flush=True)
    completed = subprocess.run(cmd)
    return completed.returncode


if not os.path.isdir(input_dir):
    logging.error("Missing image folder: %s", input_dir)
    exit(1)

if not args.skip_matching:
    os.makedirs(distorted_sparse, exist_ok=True)

    exit_code = run_colmap([
        "feature_extractor",
        "--database_path", db_path,
        "--image_path", input_dir,
        "--ImageReader.single_camera", "1",
        "--ImageReader.camera_model", args.camera,
        "--FeatureExtraction.use_gpu", use_gpu,
    ])
    if exit_code != 0:
        logging.error("Feature extraction failed with code %s. Exiting.", exit_code)
        exit(exit_code)

    if args.matcher == "sequential":
        match_cmd = [
            "sequential_matcher",
            "--database_path", db_path,
            "--FeatureMatching.use_gpu", use_gpu,
            "--SequentialMatching.overlap", str(args.overlap),
            "--SequentialMatching.quadratic_overlap", "1",
        ]
    else:
        match_cmd = [
            "exhaustive_matcher",
            "--database_path", db_path,
            "--FeatureMatching.use_gpu", use_gpu,
        ]
    exit_code = run_colmap(match_cmd)
    if exit_code != 0:
        logging.error("Feature matching failed with code %s. Exiting.", exit_code)
        exit(exit_code)

    exit_code = run_colmap([
        "mapper",
        "--database_path", db_path,
        "--image_path", input_dir,
        "--output_path", distorted_sparse,
        "--Mapper.ba_global_function_tolerance", "0.000001",
    ])
    if exit_code != 0:
        logging.error("Mapper failed with code %s. Exiting.", exit_code)
        exit(exit_code)

sparse_model = os.path.join(distorted_sparse, "0")
if not os.path.isdir(sparse_model):
    model_dirs = sorted(
        os.path.join(distorted_sparse, name)
        for name in os.listdir(distorted_sparse)
        if os.path.isdir(os.path.join(distorted_sparse, name))
    ) if os.path.isdir(distorted_sparse) else []
    if not model_dirs:
        logging.error("COLMAP mapper produced no sparse model. Exiting.")
        exit(1)
    sparse_model = model_dirs[0]
    logging.warning("Using COLMAP model at %s", sparse_model)

exit_code = run_colmap([
    "image_undistorter",
    "--image_path", input_dir,
    "--input_path", sparse_model,
    "--output_path", src,
    "--output_type", "COLMAP",
])
if exit_code != 0:
    logging.error("Undistorter failed with code %s. Exiting.", exit_code)
    exit(exit_code)

sparse_out = os.path.join(src, "sparse")
os.makedirs(os.path.join(sparse_out, "0"), exist_ok=True)
for name in os.listdir(sparse_out):
    if name == "0":
        continue
    source_file = os.path.join(sparse_out, name)
    if os.path.isfile(source_file):
        shutil.move(source_file, os.path.join(sparse_out, "0", name))

if args.resize:
    print("Copying and resizing...")
    os.makedirs(os.path.join(src, "images_2"), exist_ok=True)
    os.makedirs(os.path.join(src, "images_4"), exist_ok=True)
    os.makedirs(os.path.join(src, "images_8"), exist_ok=True)
    for name in os.listdir(os.path.join(src, "images")):
        source_file = os.path.join(src, "images", name)
        for folder, scale in (("images_2", "50%"), ("images_4", "25%"), ("images_8", "12.5%")):
            destination_file = os.path.join(src, folder, name)
            shutil.copy2(source_file, destination_file)
            completed = subprocess.run([magick_exe, "mogrify", "-resize", scale, destination_file])
            if completed.returncode != 0:
                logging.error("%s resize failed with code %s. Exiting.", scale, completed.returncode)
                exit(completed.returncode)

print("Done.")
