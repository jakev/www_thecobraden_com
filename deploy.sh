#!/bin/sh

USER=root
HOST=www.thecobraden.com             
DIR=/var/www/thecobraden.com/

hugo && rsync -avz --chown=www-data:www-data --delete public/ ${USER}@${HOST}:${DIR}

exit 0
