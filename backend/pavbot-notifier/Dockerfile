FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PAVBOT_NOTIFIER_HOST=0.0.0.0 \
    PAVBOT_NOTIFIER_PORT=8080 \
    PAVBOT_NOTIFIER_DATA_DIR=/data

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY pavbot_notifier /app/pavbot_notifier

RUN useradd --create-home --uid 10001 appuser && mkdir -p /data && chown -R appuser:appuser /data
USER appuser

EXPOSE 8080

CMD ["sh", "-c", "uvicorn pavbot_notifier.server:app --host ${PAVBOT_NOTIFIER_HOST} --port ${PAVBOT_NOTIFIER_PORT}"]
