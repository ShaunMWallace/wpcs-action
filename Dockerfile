FROM texthtml/phpcs:main

RUN mkdir -p /action
RUN ls -la

COPY entrypoint.sh \
     problem-matcher.json \
     /action/

RUN ls -la /action

RUN chmod +x /action/entrypoint.sh

RUN apk update && \
    apk upgrade && \
    apk add git

ENTRYPOINT ["/action/entrypoint.sh"]
