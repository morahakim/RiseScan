FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim
WORKDIR /srv
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev
COPY app ./app
# run as an unprivileged user: the code and the venv stay root-owned and read-only to it
RUN useradd --system --uid 10001 --no-create-home app
ENV PATH="/srv/.venv/bin:$PATH" PYTHONDONTWRITEBYTECODE=1
USER app
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
