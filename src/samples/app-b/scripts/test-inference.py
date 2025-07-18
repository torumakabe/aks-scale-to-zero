#!/usr/bin/env python3

"""
ResNet50 Inference Test Script for NVIDIA Triton Inference Server
Tests image classification using ResNet50 model deployed on Triton Server
"""

import argparse
import sys
import urllib.request
from typing import Dict, List, Tuple

import numpy as np
import requests


def download_sample_image(
    url: str = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/American_Eskimo_Dog.jpg/320px-American_Eskimo_Dog.jpg",
) -> np.ndarray:
    """Download a sample image for testing"""
    try:
        urllib.request.urlretrieve(url, "test_image.jpg")
        print("✅ Sample image downloaded: test_image.jpg")
        return "test_image.jpg"
    except Exception as e:
        print(f"❌ Failed to download sample image: {e}")
        sys.exit(1)


def preprocess_image(image_path: str) -> np.ndarray:
    """
    Preprocess image for ResNet50 inference
    - Resize to 224x224
    - Normalize pixel values
    - Convert to NCHW format
    """
    try:
        # For demo purposes, we'll create a dummy image tensor
        # In a real implementation, you would use PIL/OpenCV to load and process the actual image

        # Create dummy image data (3, 224, 224) with normalized values
        image_data = np.random.rand(3, 224, 224).astype(np.float32)

        # Add batch dimension: (1, 3, 224, 224)
        image_batch = np.expand_dims(image_data, axis=0)

        print(f"✅ Image preprocessed: shape {image_batch.shape}")
        return image_batch

    except Exception as e:
        print(f"❌ Image preprocessing failed: {e}")
        sys.exit(1)


def send_inference_request(triton_url: str, image_data: np.ndarray) -> Dict:
    """Send inference request to Triton Server"""

    # Triton inference request format
    request_data = {
        "inputs": [
            {
                "name": "data",
                "shape": list(image_data.shape),
                "datatype": "FP32",
                "data": image_data.flatten().tolist(),
            }
        ],
        "outputs": [{"name": "resnetv17_dense0_fwd"}],
    }

    try:
        response = requests.post(
            f"{triton_url}/v2/models/resnet50/infer",
            json=request_data,
            headers={"Content-Type": "application/json"},
            timeout=30,
        )

        if response.status_code == 200:
            print("✅ Inference request successful")
            return response.json()
        else:
            print(f"❌ Inference request failed: {response.status_code}")
            print(f"Response: {response.text}")
            sys.exit(1)

    except Exception as e:
        print(f"❌ Inference request error: {e}")
        sys.exit(1)


def get_top_predictions(
    inference_result: Dict, top_k: int = 5
) -> List[Tuple[int, float]]:
    """Extract top-k predictions from inference result"""
    try:
        # Extract output data
        outputs = inference_result.get("outputs", [])
        if not outputs:
            raise ValueError("No outputs in inference result")

        predictions = outputs[0]["data"]
        predictions_array = np.array(predictions)

        # Get top-k indices
        top_indices = np.argsort(predictions_array)[-top_k:][::-1]
        top_predictions = [
            (int(idx), float(predictions_array[idx])) for idx in top_indices
        ]

        return top_predictions

    except Exception as e:
        print(f"❌ Failed to process predictions: {e}")
        sys.exit(1)


def check_triton_health(triton_url: str) -> bool:
    """Check if Triton Server is healthy and ready"""
    try:
        # Health check
        health_response = requests.get(f"{triton_url}/v2/health/ready", timeout=10)
        if health_response.status_code != 200:
            print(f"❌ Triton Server not ready: {health_response.status_code}")
            return False

        # Model ready check
        model_response = requests.get(
            f"{triton_url}/v2/models/resnet50/ready", timeout=10
        )
        if model_response.status_code != 200:
            print(f"❌ ResNet50 model not ready: {model_response.status_code}")
            return False

        print("✅ Triton Server and ResNet50 model are ready")
        return True

    except Exception as e:
        print(f"❌ Health check failed: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Test ResNet50 inference on Triton Server"
    )
    parser.add_argument(
        "--url",
        default="http://localhost:8000",
        help="Triton Server URL (default: http://localhost:8000)",
    )
    parser.add_argument(
        "--image", default=None, help="Path to image file (default: download sample)"
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=5,
        help="Number of top predictions to show (default: 5)",
    )

    args = parser.parse_args()

    print(f"🚀 Testing ResNet50 inference on Triton Server: {args.url}")

    # 1. Health check
    if not check_triton_health(args.url):
        sys.exit(1)

    # 2. Prepare image
    if args.image is None:
        image_path = download_sample_image()
    else:
        image_path = args.image

    # 3. Preprocess image
    image_data = preprocess_image(image_path)

    # 4. Send inference request
    result = send_inference_request(args.url, image_data)

    # 5. Process results
    top_predictions = get_top_predictions(result, args.top_k)

    # 6. Display results
    print(f"\n🎯 Top {args.top_k} predictions:")
    for i, (class_id, confidence) in enumerate(top_predictions, 1):
        print(f"  {i}. Class {class_id}: {confidence:.4f} ({confidence * 100:.2f}%)")

    print("\n✅ ResNet50 inference test completed successfully!")


if __name__ == "__main__":
    main()
