# NVIDIA Triton Inference Server with ResNet50 ONNX Model
FROM nvcr.io/nvidia/tritonserver:23.10-py3

# Install additional dependencies for model management
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create model repository directory
RUN mkdir -p /models

# Copy model configuration
COPY models/ /models/

# Copy model download script
COPY scripts/download-model.sh /opt/download-model.sh
RUN chmod +x /opt/download-model.sh

# Download ResNet50 model during build (optional - can be done at runtime)
# RUN /opt/download-model.sh

# Copy inference test script
COPY scripts/test-inference.py /opt/test-inference.py
RUN chmod +x /opt/test-inference.py

# Create a startup script that downloads model if not exists and starts Triton
RUN printf '#!/bin/bash\n\
set -e\n\
echo "🚀 Starting Triton Inference Server for ResNet50..."\n\
\n\
# Download model if not exists\n\
if [ ! -f "/models/resnet50/1/model.onnx" ]; then\n\
    echo "📥 Downloading ResNet50 model..."\n\
    /opt/download-model.sh\n\
    echo "✅ Model download completed"\n\
fi\n\
\n\
# Start Triton Inference Server\n\
echo "🔄 Starting Triton Server..."\n\
exec tritonserver --model-repository=/models --strict-model-config=false --log-verbose=1\n\
' > /opt/start-triton.sh && chmod +x /opt/start-triton.sh

# Expose Triton ports
# 8000: HTTP endpoint
# 8001: GRPC endpoint
# 8002: Metrics endpoint
EXPOSE 8000 8001 8002

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/v2/health/ready || exit 1

# Run Triton Server
CMD ["/opt/start-triton.sh"]
