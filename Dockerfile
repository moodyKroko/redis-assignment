# Minimal python base image
FROM python:3.11-slim

# set working directory in the container
WORKDIR /app

# copy the requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the app source code
COPY app.py .

# Run FastAPI using Uvicorn
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]


