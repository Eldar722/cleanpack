# Model Download Instructions

## Android Model: yolov8n.tflite

Download from:
https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n.tflite

Then place it in: `assets/models/yolov8n.tflite` (6 MB)

Alternatively, export with Python:
```bash
pip install ultralytics
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt').export(format='tflite')"
```

## Web Model: TensorFlow.js Graph

For web version, download TFLite model and convert to TF.js:
https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n_web_model/

Then place in: `web/yolov8n_web_model/`
- model.json (graph)
- model.weights.bin (weights, split into shards)

Or use tfjs-converter to convert from tflite.
