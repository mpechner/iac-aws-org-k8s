FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY publish_cert_to_secretsmanager.py .

ENTRYPOINT ["python3", "-u", "publish_cert_to_secretsmanager.py"]
