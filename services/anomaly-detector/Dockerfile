FROM localhost:5000/fraud-component:v4
WORKDIR /app
RUN pip install --no-cache-dir aiokafka==0.11.0
COPY main.py .
CMD ["python", "main.py"]
