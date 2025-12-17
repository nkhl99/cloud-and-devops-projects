FROM python:3.11 AS builder

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir --target=/install -r requirements.txt

FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /install /app/

COPY . .

EXPOSE 5000

CMD ["python3", "main.py"]