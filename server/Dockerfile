FROM oriaks/debian:latest
MAINTAINER Michael Richard <michael.richard@oriaks.com>

VOLUME /var/lib/mysql
EXPOSE 3306/tcp

COPY entrypoint.sh /entrypoint.sh
ADD clish/* /etc/clish/
RUN /entrypoint.sh install

ENTRYPOINT ["/entrypoint.sh"]
CMD ["init"]
