ARG BASE_IMAGE=python:3.12-slim
FROM ${BASE_IMAGE}
RUN pip install --no-cache-dir cryptography==50.0.2
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY --chmod=0644 htmlapp_sdk.py /usr/local/lib/python3.12/site-packages/htmlapp_sdk.py
COPY --chmod=0644 worker.py /runtime/worker.py
RUN chmod 0755 /runtime
WORKDIR /runtime
ENTRYPOINT ["python", "-I", "/runtime/worker.py"]
