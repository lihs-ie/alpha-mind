FROM python:3.14-slim

WORKDIR /app

COPY pyproject.toml requirements.txt ./
COPY src/ src/

RUN pip install --no-cache-dir -e ".[dev]"

EXPOSE 8080

ENV PORT=8080
ENV PYTHONUNBUFFERED=1

CMD ["python", "src/main.py"]
