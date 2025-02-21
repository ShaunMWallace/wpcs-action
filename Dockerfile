FROM texthtml/phpcs:main

# Create the action directory
RUN mkdir -p /action

# Copy in your files
COPY entrypoint.sh problem-matcher.json /action/

# Make the script executable
RUN chmod +x /action/entrypoint.sh

# Install git and bash
RUN apk update && \
    apk upgrade && \
    apk add --no-cache git bash

# Switch to bash in your script by using #!/usr/bin/env bash as the shebang
# Make sure your entrypoint.sh starts with:
# #!/usr/bin/env bash

ENTRYPOINT ["/action/entrypoint.sh"]
