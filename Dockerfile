# FROM public.ecr.aws/lambda/python:3.8.2021.12.18.01-x86_64
FROM public.ecr.aws/lambda/python:3.9

ARG TELEGRAM_TOKEN
ARG TELEGRAM_CHAT_ID

ENV TELEGRAM_TOKEN=${TELEGRAM_TOKEN}
ENV TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}

# Copy requirements.txt
COPY requirements.txt ${LAMBDA_TASK_ROOT}

# Install the specified packages
RUN pip install -r requirements.txt

# Copy function code
COPY main.py ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler (could also be done as a parameter override outside of the Dockerfile)
CMD [ "main.lambda_handler" ]