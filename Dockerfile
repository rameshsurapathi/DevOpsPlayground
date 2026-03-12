FROM nginx:alpine

# Security Patch: Pull the latest security updates from Alpine repositories
RUN apk update && apk upgrade --no-cache

COPY ai-news-portal /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]