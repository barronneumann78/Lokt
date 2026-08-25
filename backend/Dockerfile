# Lokt AI backend — single-file Node server, zero npm deps.
# Secrets (OPENAI_API_KEY, APP_TOKEN, ...) come from the platform's env
# settings, never from this image. See backend/DEPLOY.md.
FROM node:22-slim

WORKDIR /app
COPY server.mjs ./

ENV NODE_ENV=production
ENV PORT=8787
EXPOSE 8787

CMD ["node", "server.mjs"]
