FROM docker.io/lmscommunity/lyrionmusicserver:9.1.1

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY custom-convert.conf custom-types.conf /lms/
