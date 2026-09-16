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
from argparse import ArgumentParser
import shutil

# This Python script is based on the shell converter script provided in the MipNerF 360 repository.
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


def q(path):
    return '"{}"'.format(os.path.normpath(path))


colmap_command = q(args.colmap_executable) if len(args.colmap_executable) > 0 else "colmap"
magick_command = q(args.magick_executable) if len(args.magick_executable) > 0 else "magick"
use_gpu = 1 if not args.no_gpu else 0
src = args.source_path
input_dir = os.path.join(src, "input")
db_path = os.path.join(src, "distorted", "database.db")
distorted_sparse = os.path.join(src, "distorted", "sparse")

if not args.skip_matching:
    os.makedirs(distorted_sparse, exist_ok=True)

    ## Feature extraction
    feat_extracton_cmd = (
        colmap_command + " feature_extractor"
        " --database_path " + q(db_path) +
        " --image_path " + q(input_dir) +
        " --ImageReader.single_camera 1"
        " --ImageReader.camera_model " + args.camera +
        " --FeatureExtraction.use_gpu " + str(use_gpu)
    )
    exit_code = os.system(feat_extracton_cmd)
    if exit_code != 0:
        logging.error(f"Feature extraction failed with code {exit_code}. Exiting.")
        exit(exit_code)

    ## Feature matching
    if args.matcher == "sequential":
        feat_matching_cmd = (
            colmap_command + " sequential_matcher"
            " --database_path " + q(db_path) +
            " --FeatureMatching.use_gpu " + str(use_gpu) +
            " --SequentialMatching.overlap " + str(args.overlap) +
            " --SequentialMatching.quadratic_overlap 1"
        )
    else:
        feat_matching_cmd = (
            colmap_command + " exhaustive_matcher"
            " --database_path " + q(db_path) +
            " --FeatureMatching.use_gpu " + str(use_gpu)
        )
    exit_code = os.system(feat_matching_cmd)
    if exit_code != 0:
        logging.error(f"Feature matching failed with code {exit_code}. Exiting.")
        exit(exit_code)

    ### Bundle adjustment
    mapper_cmd = (
        colmap_command + " mapper"
        " --database_path " + q(db_path) +
        " --image_path " + q(input_dir) +
        " --output_path " + q(distorted_sparse) +
        " --Mapper.ba_global_function_tolerance=0.000001"
    )
    exit_code = os.system(mapper_cmd)
    if exit_code != 0:
        logging.error(f"Mapper failed with code {exit_code}. Exiting.")
        exit(exit_code)

### Image undistortion
sparse_model = os.path.join(distorted_sparse, "0")
if not os.path.isdir(sparse_model):
    model_dirs = sorted(
        os.path.join(distorted_sparse, name)
        for name in os.listdir(distorted_sparse)
        if os.path.isdir(os.path.join(distorted_sparse, name))
    )
    if not model_dirs:
        logging.error("COLMAP mapper produced no sparse model. Exiting.")
        exit(1)
    sparse_model = model_dirs[0]
    logging.warning("Using COLMAP model at %s", sparse_model)

img_undist_cmd = (
    colmap_command + " image_undistorter"
    " --image_path " + q(input_dir) +
    " --input_path " + q(sparse_model) +
    " --output_path " + q(src) +
    " --output_type COLMAP"
)
exit_code = os.system(img_undist_cmd)
if exit_code != 0:
    logging.error(f"Mapper failed with code {exit_code}. Exiting.")
    exit(exit_code)

files = os.listdir(args.source_path + "/sparse")
os.makedirs(args.source_path + "/sparse/0", exist_ok=True)
# Copy each file from the source directory to the destination directory
for file in files:
    if file == '0':
        continue
    source_file = os.path.join(args.source_path, "sparse", file)
    destination_file = os.path.join(args.source_path, "sparse", "0", file)
    shutil.move(source_file, destination_file)

if(args.resize):
    print("Copying and resizing...")

    # Resize images.
    os.makedirs(args.source_path + "/images_2", exist_ok=True)
    os.makedirs(args.source_path + "/images_4", exist_ok=True)
    os.makedirs(args.source_path + "/images_8", exist_ok=True)
    # Get the list of files in the source directory
    files = os.listdir(args.source_path + "/images")
    # Copy each file from the source directory to the destination directory
    for file in files:
        source_file = os.path.join(args.source_path, "images", file)

        destination_file = os.path.join(args.source_path, "images_2", file)
        shutil.copy2(source_file, destination_file)
        exit_code = os.system(magick_command + " mogrify -resize 50% " + q(destination_file))
        if exit_code != 0:
            logging.error(f"50% resize failed with code {exit_code}. Exiting.")
            exit(exit_code)

        destination_file = os.path.join(args.source_path, "images_4", file)
        shutil.copy2(source_file, destination_file)
        exit_code = os.system(magick_command + " mogrify -resize 25% " + q(destination_file))
        if exit_code != 0:
            logging.error(f"25% resize failed with code {exit_code}. Exiting.")
            exit(exit_code)

        destination_file = os.path.join(args.source_path, "images_8", file)
        shutil.copy2(source_file, destination_file)
        exit_code = os.system(magick_command + " mogrify -resize 12.5% " + q(destination_file))
        if exit_code != 0:
            logging.error(f"12.5% resize failed with code {exit_code}. Exiting.")
            exit(exit_code)

print("Done.")
