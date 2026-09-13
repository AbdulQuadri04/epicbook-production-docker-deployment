# Stage 1: Install production dependencies
FROM node:22-alpine AS dependencies

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci --omit=dev


# Stage 2: Production runtime
FROM node:22-alpine AS runtime

WORKDIR /app

COPY --from=dependencies /app/node_modules ./node_modules

COPY --chown=node:node . .

ENV NODE_ENV=production

USER node

EXPOSE 8080

CMD ["npm", "start"]
