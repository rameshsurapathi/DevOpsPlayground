FROM nginx:alpine

COPY ai-news-portal /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]