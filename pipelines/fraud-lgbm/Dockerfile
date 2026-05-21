FROM python:3.11 AS base
FROM python:3.11-slim
COPY --from=base /usr/lib/x86_64-linux-gnu/libgomp.so.1 /usr/lib/x86_64-linux-gnu/libgomp.so.1
COPY --from=base /usr/lib/x86_64-linux-gnu/libgomp.so.1.0.0 /usr/lib/x86_64-linux-gnu/libgomp.so.1.0.0
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
