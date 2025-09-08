from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.get("/")
def root():
    return jsonify({"service": "api", "message": "Hello from API"})

@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200

@app.get("/work")
def work():
    total = sum(i*i for i in range(10000))
    return jsonify({"result": total})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
