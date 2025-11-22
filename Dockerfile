FROM nixos/nix:latest

# Set environment variables for the new user
ENV USER=user
ENV HOME=/home/user

RUN nix-channel --update

RUN mkdir -p $HOME/lightning-node-flake \
             $HOME/lightning-node-flake/config \
             $HOME/.caddy \
             $HOME/.config/nix && \
    echo "experimental-features = nix-command flakes" > $HOME/.config/nix/nix.conf

COPY caddyfile/Caddyfile $HOME/.caddy

WORKDIR $HOME

CMD ["/bin/sh", "-c", "while true; do sleep 3600; done"]