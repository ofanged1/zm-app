#ZoneMinder container

The data paths are exported from /var/lib/mysql and /usr/share/zoneminder
You can set the env variable ZM_MYSQL_HOST to anything other than localhost or 127.0.0.1
to skip db setup and update connection string to use remote db server, eg. with docker-compose
and official mysql or a shared mysql container or server.

Build the container
```
$ docker build -t fdir/zm-app .
```

Run the container
```
$ docker run -itd --name zm \
  -p 9080:80 \
  -v zm-mysql:/var/lib/mysql \
  -v zm-data:/usr/share/zoneminder \
  fdir/zm-app
&& docker logs -f zm
```


