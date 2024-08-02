# Install dependencies only when needed
FROM registry.access.redhat.com/ubi8/nodejs-18 AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
# USER root
# RUN yum -y install libc6-compat
WORKDIR /app
COPY package.json yarn.lock ./
RUN npm install --global yarn
# Add yarn timeout to handle slow CPU when Github Actions
RUN yarn config set network-timeout 300000
RUN yarn install --frozen-lockfile

# Rebuild the source code only when needed
FROM registry.access.redhat.com/ubi8/nodejs-18 AS builder
RUN npm install --global yarn
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
COPY docker/middleware.js ./src

ARG DATABASE_TYPE
ARG BASE_PATH

ENV DATABASE_TYPE $DATABASE_TYPE
ENV BASE_PATH $BASE_PATH

ENV NEXT_TELEMETRY_DISABLED 1

USER root
RUN yarn build-docker

# Production image, copy all the files and run next
FROM registry.access.redhat.com/ubi8/nodejs-18 AS runner
USER root
RUN yum -y install shadow-utils
RUN npm install --global yarn

WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

RUN groupadd --system --gid 1501 nodejs
RUN useradd --system --uid 1501 nextjs

RUN set -x \
    && yum -y install curl \
    && yarn add npm-run-all dotenv prisma semver
USER nextjs

# You only need to copy next.config.js if you are NOT using the default configuration
# COPY --from=builder /app/next.config.js .
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

EXPOSE 3000

ENV HOSTNAME 0.0.0.0
ENV PORT 3000

CMD ["yarn", "start-docker"]
