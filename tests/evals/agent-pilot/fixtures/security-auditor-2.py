"""Thumbnail generation for uploaded images."""

import subprocess


def convert_image(input_path, output_fmt):
    cmd = f"convert {input_path} output.{output_fmt}"
    subprocess.run(cmd, shell=True)
