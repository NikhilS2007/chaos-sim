FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY worker.py /app/worker.py
RUN pip install --no-cache-dir requests
CMD ["python", "worker.py"]
