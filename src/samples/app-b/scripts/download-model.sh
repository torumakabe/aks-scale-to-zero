#!/bin/bash

# ResNet50 ONNX Model Download Script
# Downloads a pre-trained ResNet50 model in ONNX format for Triton Inference Server

set -e

MODEL_DIR="/models/resnet50/1"
MODEL_FILE="$MODEL_DIR/model.onnx"

echo "Downloading ResNet50 ONNX model..."

# Create model directory if it doesn't exist
mkdir -p "$MODEL_DIR"

# Download ResNet50 ONNX model from ONNX Model Zoo
# Using a lightweight alternative ResNet50 model that's optimized for inference
curl -L -o "$MODEL_FILE" \
  "https://github.com/onnx/models/raw/main/validated/vision/classification/resnet/model/resnet50-v1-7.onnx"

if [ -f "$MODEL_FILE" ]; then
    echo "✅ ResNet50 model downloaded successfully to: $MODEL_FILE"
    echo "File size: $(ls -lh "$MODEL_FILE" | awk '{print $5}')"
else
    echo "❌ Failed to download ResNet50 model"
    exit 1
fi

echo "Model download completed. Ready for Triton Inference Server."
